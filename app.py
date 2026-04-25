import sys
import os
import re
import json
import uuid
import shlex
import shutil
import logging
import datetime
import subprocess
import threading
import queue
from flask import Flask, render_template, request, jsonify, send_from_directory, Response, stream_with_context

app = Flask(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BASE_DIR         = os.path.dirname(os.path.abspath(__file__))
DATA_FILE        = os.path.join(BASE_DIR, "data.json")
HISTORY_FILE     = os.path.join(BASE_DIR, "history.json")
TOOLS_CLONE_DIR  = os.path.join(BASE_DIR, "tools")
DATA_OUTPUT_DIR  = os.path.join(BASE_DIR, "data")

# Maximum history entries stored (prevents unbounded file growth)
MAX_HISTORY_ENTRIES = 500

# Default command timeout (seconds). Individual tools can override via "timeout" key.
DEFAULT_TIMEOUT = 300

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------
def load_json_data(filepath, default_data=None):
    if default_data is None:
        default_data = []
    if not os.path.exists(filepath):
        save_json_data(filepath, default_data)
        return default_data
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as exc:
        logger.error("Error loading %s: %s", filepath, exc)
        return default_data


def save_json_data(filepath, data):
    try:
        tmp = filepath + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, filepath)          # atomic on POSIX
    except IOError as exc:
        logger.error("Error saving %s: %s", filepath, exc)


# ---------------------------------------------------------------------------
# Input sanitization helpers
# ---------------------------------------------------------------------------
_SAFE_ID_RE = re.compile(r'^[\w\-]{1,128}$')


def is_safe_id(value: str) -> bool:
    """Accept only alphanumeric, dash, underscore — no path characters."""
    return bool(_SAFE_ID_RE.match(value))


def sanitize_for_filename(value: str, max_len: int = 40) -> str:
    """Strip everything that isn't safe for a filename component."""
    return re.sub(r'[^\w.\-]', '_', str(value))[:max_len]


# ---------------------------------------------------------------------------
# Command execution — uses a list (never shell=True) to prevent injection
# ---------------------------------------------------------------------------
def build_command_list(command_str: str) -> list:
    """
    Split a command string into a list using shlex so that the OS exec
    receives a proper argv rather than a shell-interpreted string.
    We explicitly set shell=False in Popen (the default) for safety.
    """
    try:
        return shlex.split(command_str)
    except ValueError as exc:
        raise ValueError(f"Invalid command string: {exc}") from exc


def run_command(
    cmd: list | str,
    timeout: int = DEFAULT_TIMEOUT,
    cwd: str | None = None,
) -> tuple[str, str, bool]:
    """
    Run *cmd* (list preferred, string accepted) and return (stdout, stderr, success).
    Never uses shell=True.
    """
    if isinstance(cmd, str):
        try:
            cmd = build_command_list(cmd)
        except ValueError as exc:
            return "", str(exc), False

    log_cmd = " ".join(shlex.quote(c) for c in cmd)
    logger.info("Running: %s  (cwd=%s)", log_cmd, cwd or os.getcwd())

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=cwd,
            errors="replace",
        )
        stdout, stderr = proc.communicate(timeout=timeout)
        success = proc.returncode == 0
        if not success:
            logger.warning("Command exited %d: %s", proc.returncode, log_cmd)
        return stdout, stderr, success

    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        msg = f"Command timed out after {timeout}s: {cmd[0]}"
        logger.error(msg)
        return "", msg, False

    except FileNotFoundError:
        msg = f"Command not found: {cmd[0]}. Is it installed and in PATH?"
        logger.error(msg)
        return "", msg, False

    except Exception as exc:
        msg = f"Unexpected error running {cmd[0]}: {exc}"
        logger.exception(msg)
        return "", msg, False


def run_command_streaming(
    cmd: list | str,
    timeout: int = DEFAULT_TIMEOUT,
    cwd: str | None = None,
):
    """
    Generator that yields stdout lines in real-time, then a final status line.
    Yields strings (each ending with '\\n').
    """
    if isinstance(cmd, str):
        try:
            cmd = build_command_list(cmd)
        except ValueError as exc:
            yield f"[ERROR] {exc}\n"
            return

    log_cmd = " ".join(shlex.quote(c) for c in cmd)
    logger.info("Streaming: %s  (cwd=%s)", log_cmd, cwd or os.getcwd())

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,   # merge stderr into stdout stream
            text=True,
            cwd=cwd,
            errors="replace",
        )

        # Read with a deadline using a reader thread + queue
        line_q: queue.Queue = queue.Queue()
        done_event = threading.Event()

        def reader():
            try:
                for line in proc.stdout:
                    line_q.put(line)
            finally:
                done_event.set()

        t = threading.Thread(target=reader, daemon=True)
        t.start()

        deadline = datetime.datetime.utcnow() + datetime.timedelta(seconds=timeout)
        while not done_event.is_set() or not line_q.empty():
            if datetime.datetime.utcnow() > deadline:
                proc.kill()
                yield "[ERROR] Command timed out.\n"
                return
            try:
                yield line_q.get(timeout=0.1)
            except queue.Empty:
                continue

        proc.wait()
        if proc.returncode != 0:
            yield f"\n[EXIT CODE {proc.returncode}]\n"
        else:
            yield "\n[DONE]\n"

    except FileNotFoundError:
        yield f"[ERROR] Command not found: {cmd[0]}\n"
    except Exception as exc:
        yield f"[ERROR] {exc}\n"


# ---------------------------------------------------------------------------
# Template substitution — safe quoting of each individual value
# ---------------------------------------------------------------------------
def substitute_template(template: str, replacements: dict[str, str]) -> str:
    """
    Replace {{key}} tokens with shell-quoted values.
    Raises ValueError if any placeholder remains after substitution.
    """
    result = template
    for key, value in replacements.items():
        result = result.replace(f"{{{{{key}}}}}", shlex.quote(str(value)))
    # Detect leftover placeholders — but skip literal {{ }} in bash/python snippets
    # by looking specifically for our {{word}} pattern
    remaining = re.findall(r'\{\{[\w_]+\}\}', result)
    if remaining:
        raise ValueError(f"Unresolved placeholders: {', '.join(remaining)}")
    return result


def build_replacements(tool_config: dict, user_inputs: dict) -> dict:
    """Build the substitution map from tool field definitions + user inputs."""
    replacements = {}
    for field in tool_config.get("input_fields", []):
        fid = field["id"]
        value = user_inputs.get(fid, field.get("default_value", ""))
        replacements[fid] = str(value)
    return replacements


# ---------------------------------------------------------------------------
# Custom handlers — add new entries here instead of hardcoding tool IDs
# ---------------------------------------------------------------------------
def _handle_ffuf_file_finder(tool_config: dict, user_inputs: dict):
    """
    Custom handler for the ffuf-file-finder tool.
    Returns (final_output_str, success_bool).
    """
    domain      = user_inputs.get("domain", "").strip()
    filenames   = user_inputs.get("filenames", "").strip()
    protocol    = user_inputs.get("protocol", "https").strip()

    if not domain or not filenames:
        return "Error: Domain and Filenames are required.", False

    # Write temp wordlist
    wl_name = f"_ffuf_wl_{uuid.uuid4().hex[:8]}.txt"
    wl_path = os.path.join(DATA_OUTPUT_DIR, wl_name)
    out_name = f"_ffuf_out_{uuid.uuid4().hex[:8]}.json"
    out_path = os.path.join(DATA_OUTPUT_DIR, out_name)

    try:
        lines = [ln.strip().lstrip("/") for ln in filenames.splitlines() if ln.strip()]
        if not lines:
            return "Error: No valid filenames provided.", False
        with open(wl_path, "w") as fh:
            fh.write("\n".join(lines) + "\n")

        cmd_str = tool_config["command_template"]
        cmd_str = cmd_str.replace("{{wordlist_path}}", shlex.quote(wl_path))
        cmd_str = cmd_str.replace("{{ffuf_json_output_path}}", shlex.quote(out_path))
        cmd_str = cmd_str.replace("{{protocol}}", shlex.quote(protocol))
        cmd_str = cmd_str.replace("{{domain}}", shlex.quote(domain))

        stdout, stderr, ok = run_command(cmd_str)
        output = f"FFUF Output:\n{stdout}"
        if stderr:
            output += f"\nStderr:\n{stderr}"
        output += "\n\nParsed Results (HTTP 200):\n"

        if os.path.exists(out_path):
            try:
                with open(out_path) as jf:
                    data = json.load(jf)
                results = data.get("results", [])
                if results:
                    for r in results:
                        output += f"  {r.get('url')}  [status={r.get('status')} size={r.get('length')}]\n"
                else:
                    output += "  No files found.\n"
            except json.JSONDecodeError:
                output += "  (Could not parse FFUF JSON output)\n"
        else:
            output += "  (FFUF JSON output file was not created — see console output above)\n"

        return output, ok

    finally:
        for p in (wl_path, out_path):
            try:
                if os.path.exists(p):
                    os.remove(p)
            except OSError:
                pass


# Map tool IDs to their custom handler functions
CUSTOM_HANDLERS: dict = {
    "ffuf-file-finder": _handle_ffuf_file_finder,
}


# ---------------------------------------------------------------------------
# Output filename resolver
# ---------------------------------------------------------------------------
def resolve_output_filename(pattern: str, tool_config: dict, user_inputs: dict, timestamp: str) -> str:
    name = pattern
    tool_name_safe = sanitize_for_filename(tool_config["name"].lower())
    name = name.replace("{{TOOL_ID}}", tool_config["id"])
    name = name.replace("{{TOOL_NAME_SANITIZED}}", tool_name_safe)
    name = name.replace("{{TIMESTAMP}}", timestamp)
    name = name.replace("{{UUID}}", uuid.uuid4().hex[:8])
    for field in tool_config.get("input_fields", []):
        fid = field["id"]
        val = sanitize_for_filename(str(user_inputs.get(fid, "")))
        name = name.replace(f"{{{{INPUT__{fid}}}}}", val)
        # Also handle bare {{field_id}} patterns used in some tool configs
        name = name.replace(f"{{{{{fid}}}}}", val)
    # Final safety pass — keep only safe characters
    name = re.sub(r'[^\w.\-]', '_', name)
    return name or f"output_{timestamp}.txt"


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    return render_template("index.html")


# --- Tool CRUD ---

@app.route("/api/tools", methods=["GET"])
def get_tools():
    return jsonify(load_json_data(DATA_FILE))


@app.route("/api/tools", methods=["POST"])
def add_tool():
    data = request.get_json(silent=True) or {}
    name     = (data.get("name") or "").strip()
    template = (data.get("command_template") or "").strip()

    if not name or not template:
        return jsonify({"error": "Missing required fields: name, command_template"}), 400

    tools = load_json_data(DATA_FILE)

    new_tool = {
        "id":                     str(uuid.uuid4()),
        "name":                   name,
        "description":            data.get("description", ""),
        "notes":                  data.get("notes", ""),
        "command_template":       template,
        "input_fields":           data.get("input_fields", []),
        "requires_clone":         bool(data.get("requires_clone", False)),
        "clone_url":              data.get("clone_url", ""),
        "clone_dir":              "",
        "requirements_file":      data.get("requirements_file", ""),
        "run_in_directory":       None,
        "output_filename_pattern": data.get(
            "output_filename_pattern",
            "{{TOOL_NAME_SANITIZED}}_{{TIMESTAMP}}.txt",
        ),
        "custom_handling":        bool(data.get("custom_handling", False)),
        "timeout":                int(data.get("timeout", DEFAULT_TIMEOUT)),
    }

    install_log = ""
    message     = f"Tool '{name}' added."

    if new_tool["requires_clone"] and new_tool["clone_url"]:
        slug = re.sub(r'\W+', '_', name.lower())
        rel_path = os.path.join("tools", slug)
        abs_path = os.path.join(BASE_DIR, rel_path)
        new_tool["clone_dir"] = rel_path

        if os.path.exists(abs_path):
            install_log += f"Directory {abs_path} already exists — skipping clone.\n"
        else:
            os.makedirs(os.path.dirname(abs_path), exist_ok=True)
            _, stderr, ok = run_command(
                ["git", "clone", new_tool["clone_url"], abs_path],
                timeout=300,
            )
            install_log += f"Clone: {'OK' if ok else 'FAILED'}\n{stderr}\n"
            if not ok:
                return jsonify({"error": "Clone failed", "details": stderr, "tool_config": new_tool}), 500

        if new_tool["requirements_file"]:
            req_abs = os.path.join(abs_path, new_tool["requirements_file"])
            # Path traversal guard
            if os.path.commonpath([req_abs, abs_path]) == abs_path and os.path.exists(req_abs):
                pip = os.path.join(os.path.dirname(sys.executable), "pip")
                _, pip_err, pip_ok = run_command(
                    [pip, "install", "-r", req_abs],
                    timeout=300,
                    cwd=abs_path,
                )
                install_log += f"pip install: {'OK' if pip_ok else 'FAILED'}\n{pip_err}\n"
                if not pip_ok:
                    message += " (pip install may have failed — check install_log)"
            else:
                install_log += f"requirements file '{req_abs}' not found — skipping pip.\n"

        if data.get("run_in_cloned_directory", False):
            new_tool["run_in_directory"] = rel_path

    tools.append(new_tool)
    save_json_data(DATA_FILE, tools)
    return jsonify({"message": message, "tool": new_tool, "install_log": install_log}), 201


@app.route("/api/tools/<tool_id>", methods=["PUT"])
def update_tool(tool_id):
    if not is_safe_id(tool_id):
        return jsonify({"error": "Invalid tool ID"}), 400

    data  = request.get_json(silent=True) or {}
    tools = load_json_data(DATA_FILE)
    tool  = next((t for t in tools if t["id"] == tool_id), None)
    if not tool:
        return jsonify({"error": "Tool not found"}), 404

    updatable = [
        "name", "description", "notes", "command_template",
        "input_fields", "output_filename_pattern", "custom_handling",
        "requires_clone", "clone_url", "requirements_file", "timeout",
    ]
    for key in updatable:
        if key in data:
            tool[key] = data[key]

    # run_in_directory logic
    if tool.get("requires_clone") and data.get("run_in_cloned_directory") is not None:
        slug = re.sub(r'\W+', '_', tool["name"].lower())
        tool["run_in_directory"] = os.path.join("tools", slug) if data["run_in_cloned_directory"] else None
    elif not tool.get("requires_clone"):
        tool["run_in_directory"] = None

    save_json_data(DATA_FILE, tools)
    return jsonify({"message": "Tool updated", "tool": tool})


@app.route("/api/tools/<tool_id>", methods=["DELETE"])
def delete_tool(tool_id):
    if not is_safe_id(tool_id):
        return jsonify({"error": "Invalid tool ID"}), 400

    tools = load_json_data(DATA_FILE)
    tool  = next((t for t in tools if t["id"] == tool_id), None)
    if not tool:
        return jsonify({"error": "Tool not found"}), 404

    msg = f"Tool '{tool['name']}' removed."

    if tool.get("requires_clone") and tool.get("clone_dir"):
        target_abs   = os.path.abspath(os.path.join(BASE_DIR, tool["clone_dir"]))
        tools_dir_abs = os.path.abspath(TOOLS_CLONE_DIR)
        if target_abs.startswith(tools_dir_abs + os.sep) and os.path.isdir(target_abs):
            try:
                shutil.rmtree(target_abs)
                msg += f" Directory '{tool['clone_dir']}' deleted."
            except Exception as exc:
                msg += f" Could not delete directory: {exc}"
        else:
            msg += " Directory not in expected location — not deleted."

    tools = [t for t in tools if t["id"] != tool_id]
    save_json_data(DATA_FILE, tools)
    return jsonify({"message": msg})


# --- Tool execution (standard — full output returned at once) ---

@app.route("/api/run_tool/<tool_id>", methods=["POST"])
def run_tool(tool_id):
    if not is_safe_id(tool_id):
        return jsonify({"error": "Invalid tool ID"}), 400

    user_inputs = request.get_json(silent=True) or {}
    tools_data  = load_json_data(DATA_FILE)
    tool        = next((t for t in tools_data if t["id"] == tool_id), None)

    if not tool:
        return jsonify({"error": "Tool not found"}), 404

    timestamp  = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    timeout    = int(tool.get("timeout", DEFAULT_TIMEOUT))
    final_out  = ""
    success    = False

    # --- Custom handler path ---
    handler = CUSTOM_HANDLERS.get(tool_id) if tool.get("custom_handling") else None
    if handler:
        final_out, success = handler(tool, user_inputs)

    # --- Standard path ---
    else:
        try:
            replacements = build_replacements(tool, user_inputs)
            cmd_str      = substitute_template(tool["command_template"], replacements)
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

        cwd = _resolve_cwd(tool)
        stdout, stderr, success = run_command(cmd_str, timeout=timeout, cwd=cwd)
        final_out = stdout
        if stderr:
            final_out += f"\n--- stderr ---\n{stderr}"

    # --- Persist output ---
    out_file_rel = _save_output(tool, user_inputs, final_out, timestamp)

    # --- History ---
    _append_history(tool, user_inputs, out_file_rel, success, final_out)

    return jsonify({
        "output":      final_out,
        "output_file": out_file_rel,
        "status":      "success" if success else "error",
    })


# --- Tool execution (streaming via Server-Sent Events) ---

@app.route("/api/run_tool_stream/<tool_id>", methods=["POST"])
def run_tool_stream(tool_id):
    """
    Stream tool output line-by-line using Server-Sent Events (SSE).
    The client should listen with EventSource or fetch+ReadableStream.
    Custom-handled tools fall back to the standard non-streaming endpoint.
    """
    if not is_safe_id(tool_id):
        return jsonify({"error": "Invalid tool ID"}), 400

    user_inputs = request.get_json(silent=True) or {}
    tools_data  = load_json_data(DATA_FILE)
    tool        = next((t for t in tools_data if t["id"] == tool_id), None)

    if not tool:
        return jsonify({"error": "Tool not found"}), 404

    if tool.get("custom_handling"):
        # Custom tools don't stream — delegate to standard endpoint
        return run_tool(tool_id)

    try:
        replacements = build_replacements(tool, user_inputs)
        cmd_str      = substitute_template(tool["command_template"], replacements)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    cwd     = _resolve_cwd(tool)
    timeout = int(tool.get("timeout", DEFAULT_TIMEOUT))

    # Buffer all output for saving after stream completes
    output_buffer: list[str] = []
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

    def generate():
        for line in run_command_streaming(cmd_str, timeout=timeout, cwd=cwd):
            output_buffer.append(line)
            # SSE format: "data: <payload>\n\n"
            yield f"data: {json.dumps(line)}\n\n"

        full_output = "".join(output_buffer)
        success     = not full_output.rstrip().endswith("[EXIT CODE") and "[ERROR]" not in full_output
        out_file    = _save_output(tool, user_inputs, full_output, timestamp)
        _append_history(tool, user_inputs, out_file, success, full_output)
        yield f"data: {json.dumps({'__done__': True, 'output_file': out_file, 'status': 'success' if success else 'error'})}\n\n"

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={
            "Cache-Control":  "no-cache",
            "X-Accel-Buffering": "no",   # disable nginx buffering if behind proxy
        },
    )


# --- History ---

@app.route("/api/history/<tool_id>", methods=["GET"])
def get_tool_history(tool_id):
    if not is_safe_id(tool_id):
        return jsonify({"error": "Invalid tool ID"}), 400
    history = load_json_data(HISTORY_FILE)
    return jsonify([e for e in history if e.get("tool_id") == tool_id])


@app.route("/api/history", methods=["GET"])
def get_all_history():
    """Return the N most recent history entries across all tools."""
    limit = min(int(request.args.get("limit", 100)), MAX_HISTORY_ENTRIES)
    return jsonify(load_json_data(HISTORY_FILE)[:limit])


@app.route("/api/history", methods=["DELETE"])
def clear_history():
    """Clear all history entries and optionally delete output files."""
    purge_files = request.args.get("purge_files", "false").lower() == "true"
    history = load_json_data(HISTORY_FILE)
    if purge_files:
        for entry in history:
            fp = os.path.join(BASE_DIR, entry.get("output_file", ""))
            if os.path.exists(fp) and os.path.abspath(fp).startswith(os.path.abspath(DATA_OUTPUT_DIR)):
                try:
                    os.remove(fp)
                except OSError:
                    pass
    save_json_data(HISTORY_FILE, [])
    return jsonify({"message": "History cleared."})


@app.route("/api/history_file_content", methods=["GET"])
def get_history_file_content():
    filepath_relative = request.args.get("filepath", "")
    if not filepath_relative:
        return jsonify({"error": "filepath parameter required"}), 400

    requested_abs      = os.path.abspath(os.path.join(BASE_DIR, filepath_relative))
    data_output_abs    = os.path.abspath(DATA_OUTPUT_DIR)

    # Strict path traversal guard
    if not requested_abs.startswith(data_output_abs + os.sep):
        logger.warning("Path traversal attempt: %s", filepath_relative)
        return jsonify({"error": "Access denied"}), 403

    if not os.path.isfile(requested_abs):
        return jsonify({"error": "File not found"}), 404

    try:
        with open(requested_abs, "r", encoding="utf-8", errors="replace") as fh:
            return jsonify({"content": fh.read(), "filepath": filepath_relative})
    except IOError as exc:
        return jsonify({"error": f"Could not read file: {exc}"}), 500


# --- Static output file download ---

@app.route("/data/<path:filename>", methods=["GET"])
def download_output(filename):
    """Serve a previously saved output file for download."""
    # Prevent path traversal
    safe_name = os.path.basename(filename)
    return send_from_directory(DATA_OUTPUT_DIR, safe_name, as_attachment=True)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------
def _resolve_cwd(tool: dict) -> str | None:
    if tool.get("run_in_directory"):
        p = os.path.join(BASE_DIR, tool["run_in_directory"])
        if os.path.isdir(p):
            return p
        logger.warning("run_in_directory '%s' not found for tool '%s'.", p, tool.get("id"))
    return None


def _save_output(tool: dict, user_inputs: dict, content: str, timestamp: str) -> str:
    pattern  = tool.get("output_filename_pattern", "{{TOOL_NAME_SANITIZED}}_{{TIMESTAMP}}.txt")
    filename = resolve_output_filename(pattern, tool, user_inputs, timestamp)
    rel_path = os.path.join("data", filename)
    abs_path = os.path.join(BASE_DIR, rel_path)
    os.makedirs(DATA_OUTPUT_DIR, exist_ok=True)
    try:
        with open(abs_path, "w", encoding="utf-8", errors="replace") as fh:
            fh.write(content)
    except IOError as exc:
        logger.error("Failed to save output file %s: %s", abs_path, exc)
    return rel_path


def _append_history(tool: dict, user_inputs: dict, out_file: str, success: bool, output: str):
    lines   = output.splitlines()
    preview = (lines[0][:120] + "…") if lines and len(lines[0]) > 120 else (lines[0] if lines else "")

    entry = {
        "history_id":  str(uuid.uuid4()),
        "tool_id":     tool["id"],
        "tool_name":   tool["name"],
        "timestamp":   datetime.datetime.now().isoformat(),
        "inputs":      user_inputs,
        "output_file": out_file,
        "status":      "success" if success else "error",
        "preview":     preview,
    }

    history = load_json_data(HISTORY_FILE)
    history.insert(0, entry)
    # Cap history size
    if len(history) > MAX_HISTORY_ENTRIES:
        history = history[:MAX_HISTORY_ENTRIES]
    save_json_data(HISTORY_FILE, history)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    os.makedirs(TOOLS_CLONE_DIR, exist_ok=True)
    os.makedirs(DATA_OUTPUT_DIR, exist_ok=True)
    # Pre-create JSON files if absent
    load_json_data(DATA_FILE)
    load_json_data(HISTORY_FILE)

    debug_mode = os.environ.get("FLASK_DEBUG", "0") == "1"
    port       = int(os.environ.get("PORT", 5001))
    host       = os.environ.get("HOST", "0.0.0.0")

    logger.info("OSINTel Dashboard starting — http://%s:%d  (debug=%s)", host, port, debug_mode)
    app.run(debug=debug_mode, host=host, port=port)