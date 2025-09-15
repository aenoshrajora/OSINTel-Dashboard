from flask import Flask, render_template, request, jsonify, send_from_directory
import subprocess
import shlex
import os
import json
import uuid
import shutil
import datetime
import re

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = os.path.join(BASE_DIR, "data.json")
HISTORY_FILE = os.path.join(BASE_DIR, "history.json")
TOOLS_CLONE_DIR = os.path.join(BASE_DIR, "tools")
DATA_OUTPUT_DIR = os.path.join(BASE_DIR, "data")


def load_json_data(filepath, default_data=None):
    if default_data is None: default_data = []
    if not os.path.exists(filepath):
        with open(filepath, 'w') as f: json.dump(default_data, f, indent=2)
        return default_data
    try:
        with open(filepath, 'r') as f: return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        app.logger.error(f"Error loading {filepath}: {e}"); return default_data

def save_json_data(filepath, data):
    try:
        with open(filepath, 'w') as f: json.dump(data, f, indent=2)
    except IOError as e: app.logger.error(f"Error saving {filepath}: {e}")

def run_command_generic(command_str, timeout=300, cwd=None):
    try:
        app.logger.info(f"Running command: {command_str} in CWD: {cwd or os.getcwd()}")
        process = subprocess.Popen(shlex.split(command_str), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=cwd, errors='replace')
        stdout, stderr = process.communicate(timeout=timeout)
        if process.returncode != 0:
            error_message = f"Error (Code {process.returncode})"
            if stderr: error_message += f"\nStderr:\n{stderr}"
            if stdout: error_message += f"\nStdout (may contain error details):\n{stdout}"
            app.logger.error(f"Command '{command_str.split()[0]}' failed: {error_message}")
            return error_message.strip(), False
        return stdout, True
    except subprocess.TimeoutExpired:
        app.logger.error(f"Command timed out: {command_str}")
        return f"Error: Command '{command_str.split()[0]}' timed out after {timeout} seconds.", False
    except FileNotFoundError:
        app.logger.error(f"Command not found: {command_str.split()[0]}")
        return f"Error: The command '{command_str.split()[0]}' was not found. Is it installed and in PATH?", False
    except Exception as e:
        app.logger.error(f"Unexpected error running command {command_str}: {str(e)}")
        return f"An unexpected error occurred: {str(e)}", False

@app.route('/')
def index(): return render_template('index.html')

@app.route('/api/tools', methods=['GET'])
def get_tools(): return jsonify(load_json_data(DATA_FILE))

@app.route('/api/tools', methods=['POST'])
def add_tool():
    data = request.get_json()
    if not data or not data.get('name') or not data.get('command_template'):
        return jsonify({"error": "Missing required tool data (name, command_template)"}), 400
    tools = load_json_data(DATA_FILE)
    new_tool = {
        "id": str(uuid.uuid4()),
        "name": data.get("name"),
        "description": data.get("description", ""),
        "notes": data.get("notes", ""),
        "command_template": data.get("command_template"),
        "input_fields": data.get("input_fields", []),
        "requires_clone": data.get("requires_clone", False),
        "clone_url": data.get("clone_url", "") if data.get("requires_clone") else "",
        "clone_dir": "", 
        "requirements_file": data.get("requirements_file", "") if data.get("requires_clone") else "",
        "run_in_directory": None,
        "output_filename_pattern": data.get("output_filename_pattern", "{{TOOL_NAME_SANITIZED}}_{{INPUT__default_input}}_{{TIMESTAMP}}.txt"),
        "custom_handling": data.get("custom_handling", False)
    }
    message = "Tool added to config."
    installation_output = ""
    if new_tool["requires_clone"] and new_tool["clone_url"]:
        tool_name_sanitized = re.sub(r'\W+', '_', new_tool["name"].lower())
        relative_clone_path = os.path.join("tools", tool_name_sanitized) 
        new_tool["clone_dir"] = relative_clone_path
        clone_target_dir_abs = os.path.join(BASE_DIR, relative_clone_path)
        if os.path.exists(clone_target_dir_abs): installation_output += f"Directory {clone_target_dir_abs} already exists. Skipping clone.\n"
        else:
            os.makedirs(os.path.dirname(clone_target_dir_abs), exist_ok=True)
            clone_command = f"git clone {shlex.quote(new_tool['clone_url'])} {shlex.quote(clone_target_dir_abs)}"
            installation_output += f"Attempting to clone: {clone_command}\n"
            clone_result, clone_success = run_command_generic(clone_command, timeout=300)
            installation_output += f"Clone result:\n{clone_result}\n"
            if not clone_success: return jsonify({"error": "Failed to clone repository.", "details": clone_result, "tool_config": new_tool}), 500
        if new_tool["requirements_file"]:
            req_file_path = os.path.join(clone_target_dir_abs, new_tool["requirements_file"])
            if os.path.exists(req_file_path) and os.path.abspath(req_file_path).startswith(os.path.abspath(clone_target_dir_abs)):
                pip_command = f"{os.path.join(os.path.dirname(sys.executable), 'pip')} install -r {shlex.quote(req_file_path)}"
                installation_output += f"Attempting to install requirements: {pip_command}\n"
                pip_result, pip_success = run_command_generic(pip_command, timeout=300, cwd=clone_target_dir_abs)
                installation_output += f"Pip install result:\n{pip_result}\n"
                if not pip_success: message += " Tool added, but pip install might have failed."
            else: installation_output += f"Requirements file {req_file_path} not found. Skipping pip install.\n"
        if data.get("run_in_cloned_directory", False): new_tool["run_in_directory"] = relative_clone_path
        message = f"Tool '{new_tool['name']}' configured. Install log:\n{installation_output}"
    tools.append(new_tool)
    save_json_data(DATA_FILE, tools)
    return jsonify({"message": message, "tool": new_tool, "installation_log": installation_output}), 201


@app.route('/api/tools/<tool_id>', methods=['PUT'])
def update_tool(tool_id):
    data = request.get_json()
    tools = load_json_data(DATA_FILE)
    tool_to_update = next((t for t in tools if t["id"] == tool_id), None)
    if not tool_to_update: return jsonify({"error": "Tool not found"}), 404
    tool_to_update["name"] = data.get("name", tool_to_update["name"])
    tool_to_update["description"] = data.get("description", tool_to_update.get("description"))
    tool_to_update["notes"] = data.get("notes", tool_to_update.get("notes"))
    tool_to_update["command_template"] = data.get("command_template", tool_to_update["command_template"])
    tool_to_update["input_fields"] = data.get("input_fields", tool_to_update.get("input_fields", []))
    tool_to_update["output_filename_pattern"] = data.get("output_filename_pattern", tool_to_update.get("output_filename_pattern", "{{TOOL_NAME_SANITIZED}}_{{INPUT__default_input}}_{{TIMESTAMP}}.txt"))
    tool_to_update["custom_handling"] = data.get("custom_handling", tool_to_update.get("custom_handling", False))
    tool_to_update["requires_clone"] = data.get("requires_clone", tool_to_update.get("requires_clone", False))
    tool_to_update["clone_url"] = data.get("clone_url", tool_to_update.get("clone_url", ""))
    tool_to_update["requirements_file"] = data.get("requirements_file", tool_to_update.get("requirements_file", ""))
    if tool_to_update["requires_clone"] and data.get("run_in_cloned_directory") is not None:
        tool_name_sanitized = re.sub(r'\W+', '_', tool_to_update["name"].lower())
        tool_to_update["run_in_directory"] = os.path.join("tools", tool_name_sanitized) if data.get("run_in_cloned_directory") else None
    elif not tool_to_update["requires_clone"]:
        tool_to_update["run_in_directory"] = None

    save_json_data(DATA_FILE, tools)
    return jsonify({"message": "Tool updated", "tool": tool_to_update})


@app.route('/api/tools/<tool_id>', methods=['DELETE'])
def delete_tool(tool_id):
    tools = load_json_data(DATA_FILE)
    tool_to_delete = next((t for t in tools if t["id"] == tool_id), None)
    if not tool_to_delete: return jsonify({"error": "Tool not found"}), 404
    deletion_message = f"Tool '{tool_to_delete['name']}' configuration removed."
    if tool_to_delete.get("requires_clone") and tool_to_delete.get("clone_dir"):
        dir_to_remove_abs = os.path.abspath(os.path.join(BASE_DIR, tool_to_delete["clone_dir"]))
        tools_clone_dir_abs = os.path.abspath(TOOLS_CLONE_DIR)
        if dir_to_remove_abs.startswith(tools_clone_dir_abs) and os.path.isdir(dir_to_remove_abs):
            try: shutil.rmtree(dir_to_remove_abs); deletion_message += f" Associated directory '{tool_to_delete['clone_dir']}' also removed."
            except Exception as e: deletion_message += f" Failed to remove directory '{tool_to_delete['clone_dir']}': {e}"
        elif os.path.exists(dir_to_remove_abs): deletion_message += f" Directory '{tool_to_delete['clone_dir']}' was not safe. Not removed."
    tools = [t for t in tools if t["id"] != tool_id]
    save_json_data(DATA_FILE, tools)
    return jsonify({"message": deletion_message})


@app.route('/api/run_tool/<tool_id>', methods=['POST'])
def run_tool_dynamic(tool_id):
    user_inputs = request.get_json()
    tools_data = load_json_data(DATA_FILE)
    tool_config = next((t for t in tools_data if t["id"] == tool_id), None)

    if not tool_config:
        return jsonify({"error": "Tool configuration not found"}), 404

    command_str_template = tool_config["command_template"]
    current_timestamp_str = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    tool_name_sanitized = re.sub(r'\W+', '_', tool_config["name"].lower())
    
    if tool_config.get("custom_handling") and tool_config["id"] == "ffuf-file-finder":
        domain = user_inputs.get("domain")
        filenames_str = user_inputs.get("filenames")
        protocol = user_inputs.get("protocol", "https")

        if not domain or not filenames_str:
            return jsonify({"error": "Domain and Filenames are required for FFUF File Finder."}), 400

        temp_wordlist_name = f"temp_wordlist_ffuf_{uuid.uuid4().hex[:8]}.txt"
        temp_wordlist_path_abs = os.path.join(DATA_OUTPUT_DIR, temp_wordlist_name)
        
        try:
            with open(temp_wordlist_path_abs, 'w') as f:
                for filename in filenames_str.splitlines():
                    fn_stripped = filename.strip()
                    if fn_stripped:
                        if fn_stripped.startswith('/'): fn_stripped = fn_stripped[1:]
                        f.write(fn_stripped + "\n")
            if os.path.getsize(temp_wordlist_path_abs) == 0:
                os.remove(temp_wordlist_path_abs)
                return jsonify({"error": "Filenames input was empty or contained no valid filenames."}), 400

        except IOError as e:
            app.logger.error(f"Failed to write temp wordlist for ffuf: {e}")
            return jsonify({"error": f"Server error creating wordlist: {e}"}), 500

        temp_ffuf_output_name = f"ffuf_out_{uuid.uuid4().hex[:8]}.json"
        temp_ffuf_output_path_abs = os.path.join(DATA_OUTPUT_DIR, temp_ffuf_output_name)

        command_str = command_str_template.replace("{{wordlist_path}}", shlex.quote(temp_wordlist_path_abs))
        command_str = command_str.replace("{{ffuf_json_output_path}}", shlex.quote(temp_ffuf_output_path_abs))
        command_str = command_str.replace("{{protocol}}", shlex.quote(protocol))
        command_str = command_str.replace("{{domain}}", shlex.quote(domain))
        
    else:
        command_str = command_str_template
        for field_config in tool_config.get("input_fields", []):
            input_id = field_config["id"]
            user_value = user_inputs.get(input_id, field_config.get("default_value", ""))
            command_str = command_str.replace(f"{{{{{input_id}}}}}", shlex.quote(str(user_value)))
    
    if "{{" in command_str and "}}" in command_str:
        if tool_config.get("custom_handling") and tool_config["id"] == "ffuf-file-finder":
            if 'temp_wordlist_path_abs' in locals() and os.path.exists(temp_wordlist_path_abs): os.remove(temp_wordlist_path_abs)
            if 'temp_ffuf_output_path_abs' in locals() and os.path.exists(temp_ffuf_output_path_abs): os.remove(temp_ffuf_output_path_abs)
        return jsonify({"error": f"Unresolved placeholders in command: {command_str}"}), 400

    cwd_path = None
    if tool_config.get("run_in_directory"):
        potential_cwd = os.path.join(BASE_DIR, tool_config["run_in_directory"])
        if os.path.isdir(potential_cwd): cwd_path = potential_cwd
        else: app.logger.warning(f"CWD {potential_cwd} not found for tool {tool_id}.")

    ffuf_console_output, success_status = run_command_generic(command_str, cwd=cwd_path)
    
    final_output_for_user = ffuf_console_output
    
    if tool_config.get("custom_handling") and tool_config["id"] == "ffuf-file-finder":
        parsed_ffuf_results = f"FFUF Console Output:\n{ffuf_console_output}\n\nParsed Found Files (Status 200):\n"
        found_count = 0
        if os.path.exists(temp_ffuf_output_path_abs):
            try:
                with open(temp_ffuf_output_path_abs, 'r') as f_json:
                    ffuf_data = json.load(f_json)
                if "results" in ffuf_data and ffuf_data["results"]:
                    for result in ffuf_data["results"]:
                        parsed_ffuf_results += f"- {result.get('url')} (Status: {result.get('status')}, Size: {result.get('length')})\n"
                        found_count +=1
                if found_count == 0:
                    parsed_ffuf_results += "No files found matching criteria (e.g., status 200).\n"
            except json.JSONDecodeError:
                parsed_ffuf_results += "Error: Could not decode FFUF's JSON output.\n"
            except Exception as e:
                parsed_ffuf_results += f"Error processing FFUF JSON: {str(e)}\n"
        else:
            parsed_ffuf_results += "FFUF JSON output file was not created. Check FFUF console output above for errors.\n"
        final_output_for_user = parsed_ffuf_results
        
        try:
            if 'temp_wordlist_path_abs' in locals() and os.path.exists(temp_wordlist_path_abs): os.remove(temp_wordlist_path_abs)
            if 'temp_ffuf_output_path_abs' in locals() and os.path.exists(temp_ffuf_output_path_abs): os.remove(temp_ffuf_output_path_abs)
        except OSError as e:
            app.logger.error(f"Error removing ffuf temp files: {e}")
            final_output_for_user += f"\nWarning: Could not remove temporary FFUF files."
    output_filename = tool_config.get("output_filename_pattern", "{{TOOL_NAME_SANITIZED}}_{{TIMESTAMP}}.txt")
    output_filename = output_filename.replace("{{TOOL_ID}}", tool_id)
    output_filename = output_filename.replace("{{TOOL_NAME_SANITIZED}}", tool_name_sanitized)
    output_filename = output_filename.replace("{{TIMESTAMP}}", current_timestamp_str)
    output_filename = output_filename.replace("{{UUID}}", str(uuid.uuid4())[:8])
    for field_config in tool_config.get("input_fields", []):
        input_id = field_config["id"]
        user_val_sanitized = re.sub(r'\W+', '_', str(user_inputs.get(input_id, "")))[:30]
        output_filename = output_filename.replace(f"{{{{INPUT__{input_id}}}}}", user_val_sanitized)
    output_filename = "".join(c if c.isalnum() or c in ['.', '_', '-'] else '_' for c in output_filename)
    output_filepath_relative = os.path.join("data", output_filename)
    output_filepath_abs = os.path.join(BASE_DIR, output_filepath_relative)
    try:
        os.makedirs(DATA_OUTPUT_DIR, exist_ok=True)
        with open(output_filepath_abs, 'w', encoding='utf-8', errors='replace') as f:
            f.write(final_output_for_user)
    except IOError as e:
        app.logger.error(f"Failed to write output file {output_filepath_abs}: {e}")

    first_line_of_output = final_output_for_user.splitlines()[0] if final_output_for_user.splitlines() else ""
    concise_preview = (first_line_of_output[:100] + "...") if len(first_line_of_output) > 100 else first_line_of_output

    history_entry = {
        "history_id": str(uuid.uuid4()), "tool_id": tool_id, "tool_name": tool_config["name"],
        "timestamp": datetime.datetime.now().isoformat(), "inputs": user_inputs,
        "output_file": output_filepath_relative, "status": "success" if success_status else "error",
        "preview": concise_preview
    }
    history_data = load_json_data(HISTORY_FILE)
    history_data.insert(0, history_entry)
    save_json_data(HISTORY_FILE, history_data)

    return jsonify({"output": final_output_for_user, "output_file": output_filepath_relative, "status": history_entry["status"]})


@app.route('/api/history/<tool_id>', methods=['GET'])
def get_tool_history(tool_id):
    history_data = load_json_data(HISTORY_FILE)
    tool_history = [entry for entry in history_data if entry["tool_id"] == tool_id]
    return jsonify(tool_history)

@app.route('/api/history_file_content', methods=['GET'])
def get_history_file_content():
    filepath_relative = request.args.get('filepath')
    if not filepath_relative: return jsonify({"error": "filepath parameter is required"}), 400
    requested_path_abs = os.path.abspath(os.path.join(BASE_DIR, filepath_relative))
    data_output_dir_abs = os.path.abspath(DATA_OUTPUT_DIR)
    if not requested_path_abs.startswith(data_output_dir_abs):
        app.logger.warning(f"Path traversal attempt: {filepath_relative}"); return jsonify({"error": "Access denied."}), 403
    if not os.path.exists(requested_path_abs): return jsonify({"error": "History file not found."}), 404
    try:
        with open(requested_path_abs, 'r', encoding='utf-8', errors='replace') as f: content = f.read()
        return jsonify({"content": content, "filepath": filepath_relative})
    except IOError as e:
        app.logger.error(f"Error reading history file {requested_path_abs}: {e}"); return jsonify({"error": f"Could not read file: {e}"}), 500

import sys 

if __name__ == '__main__':
    os.makedirs(TOOLS_CLONE_DIR, exist_ok=True)
    os.makedirs(DATA_OUTPUT_DIR, exist_ok=True)
    load_json_data(DATA_FILE) 
    load_json_data(HISTORY_FILE)
    import logging
    logging.basicConfig(level=logging.INFO)
    app.logger.info(f"Dashboard starting. Base: {BASE_DIR}, Data: {DATA_OUTPUT_DIR}")
    app.run(debug=True, host='0.0.0.0', port=5001)
