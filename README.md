# OSINTel - OSINT Dashboard

**A dynamic, Flask-based web application providing a centralized interface for executing various open-source intelligence (OSINT) and cybersecurity command-line tools.**

This dashboard allows users to:
*   Run pre-configured and user-added OSINT tools through an easy-to-use web UI.
*   Manage tool configurations (add, edit, delete).
*   View execution history for each tool.
*   Save tool outputs to files.
*   Make links in tool output clickable.

**Project Status:** Actively Developed. Open to contributions, feature requests, and feedback!

## Disclaimer

⚠️ **FOR EDUCATIONAL AND AUTHORIZED RESEARCH PURPOSES ONLY.** ⚠️

This software is intended to help users learn about OSINT techniques and cybersecurity tools in a controlled environment. The user is solely responsible for their actions and for ensuring that their use of this software complies with all applicable local, state, national, and international laws and regulations. The creators and contributors of this project assume NO liability and are NOT responsible for any misuse or damage caused by this program. **Always obtain explicit, written permission before scanning or investigating any target that you do not own or have prior authorization to test.**

## License

This project is open source and licensed under the **MIT License** - see the `LICENSE` file for details.. 

## Features

*   **Dynamic Web Interface:** Built with HTML, CSS, and JavaScript.
*   **Flask Backend:** Python-based server to manage tools and execute commands.
*   **Centralized Tooling:** Access multiple OSINT tools from a single dashboard.
*   **User-Managed Tool Configuration:**
    *   Add new tools with custom command templates, input fields, and output filename patterns.
    *   Edit existing tool configurations.
    *   Delete tools.
    *   Support for tools requiring `git clone` and `pip install requirements.txt`.
*   **Execution History:**
    *   Logs each tool run with inputs, status, and a link to the saved output file.
    *   View history per tool.
    *   Load and display past results.
*   **File-Based Output:** Full tool outputs are saved to files in a `data/` directory.
*   **Clickable Links:** URLs in tool output are automatically converted to clickable links.
*   **Interactive Setup Script (`setup.sh`):** Guides users through dependency and tool installation.

### Pre-configured Tools (via `data.json` and installable with `setup.sh`):

*   **Holehe Email Check:** Checks if an email is used on various sites.
*   **Nmap Network Scan:** Network exploration and port scanner.
*   **IP/Domain Info:** Performs WHOIS and DIG lookups.
*   **TheHarvester:** Gathers emails, subdomains, hosts, etc.
*   **Dnsrecon DNS Enumeration:** DNS enumeration and reconnaissance.
*   **WhatWeb - Website Technologies:** Identifies technologies used on websites.
*   **FFUF - Domain File Finder:** Fast web fuzzer for content discovery.
*   **Sherlock Username Search (Cloned):** Hunts for social media accounts by username.
*   **Sublist3r Subdomain Enum (Cloned):** Enumerates subdomains.
*   **GHunt Google Acct Invest. (Cloned):** Investigates Google accounts (requires manual cookie setup).
*   **Metagoofil Metadata Extr. (Cloned):** Extracts metadata from public documents.

## Tech Stack

*   **Backend:** Python 3.8+, Flask
*   **Frontend:** HTML5, CSS3, JavaScript (Vanilla)
*   **Data Storage:** JSON files (`data.json` for tool configs, `history.json` for run logs)
*   **OSINT Tools:** Various command-line utilities (see above).
*   **Environment Management:** Python `venv`
*   **Setup:** Bash Script (`setup.sh`)

## Prerequisites & System Compatibility

This project is designed and primarily tested for **Linux-based systems**, specifically on **Debian-based distributions (like Ubuntu, Kali Linux, Debian itself)**. While some components might work on other operating systems with adjustments, full functionality and the `setup.sh` script are tailored for this environment.

Before you begin, ensure your system has the following base components. The `setup.sh` script will attempt to install or verify many of these, but it's good to be aware.

*   **Python:** Version 3.8 or higher.
    *   To check: `python3 --version`
    *   To install (if missing on a Debian-based system): `sudo apt update && sudo apt install python3`
*   **`pip` (Python package installer):**
    *   To check: `pip3 --version`
    *   To install (if missing, usually comes with `python3-pip`): `sudo apt install python3-pip`
*   **`python3-venv` (for creating Python virtual environments):**
    *   To install: `sudo apt install python3-venv`
*   **`git`**: For cloning tool repositories.
    *   To check: `git --version`
    *   To install: `sudo apt install git`
*   **`curl`**: Often used by setup scripts or tools for downloads.
    *   To check: `curl --version`
    *   To install: `sudo apt install curl`

The `setup.sh` script will guide you through installing other specific command-line OSINT tools (like Nmap, FFUF, etc.) via `apt`.

## Installation

You have two primary methods for setting up the OSINT Dashboard: using the interactive `setup.sh` script (recommended for most users) or performing a manual installation.

### Method 1: Using the Interactive Setup Script (Recommended)

The `setup.sh` script automates most of the installation process, including system dependencies, Python packages, and cloning/setting up common OSINT tools.

1.  **Download/Clone Project:**
    If you haven't already, get the project files.
    ```bash
    git clone https://github.com/aenoshrajora/osintelOSINTel-Dashboard.git
    cd OSINTel-Dashboard 
    ```
    Ensure `setup.sh`, `app.py`, `data.json`, `history.json` (can be empty `[]`), and the `templates/index.html` file are in this directory.

2.  **Make `setup.sh` Executable:**
    ```bash
    chmod +x setup.sh
    ```

3.  **Run the Setup Script:**
    It's highly recommended to run the script from within a dedicated, preferably empty, project directory. The script will guide you through creating/activating a Python virtual environment.
    ```bash
    ./setup.sh
    ```
    *   The script will first check if you are in an empty directory and if a virtual environment is active/needs creation.
    *   It will then prompt you to install essential system packages (like `python3-pip`, `git`) and optional OSINT system tools (like `nmap`, `ffuf`) via `apt`. This step will require `sudo` privileges.
    *   Next, it will ask which of the common clonable OSINT tools (Sherlock, Sublist3r, etc.) you wish to install or update.
    *   Follow the on-screen prompts.
    *   **Note on `sudo`:** The script is designed to ask for `sudo` only when needed for `apt` commands.

4.  **Post-Setup Steps (CRITICAL - Read output from `setup.sh`):**
    *   **GHunt Cookies:** If you installed GHunt, you **MUST** manually generate its `cookies.json` file. Navigate to where GHunt was cloned (e.g., `./tools/GHunt/GHunt/`) and run `python3 check_and_gen_cookies.py`.
    *   **`data.json` Paths:** Verify that the `clone_dir` and `run_in_directory` paths in your `data.json` file match the actual locations where tools were cloned by the `setup.sh` script (e.g., `tools/sherlock`, `tools/Sublist3r`). The script attempts to use these standard names.
    *   **Create `data` directory:** The `setup.sh` script now creates the `./data` and `./tools` directories. If `./data` is still missing for any reason: `mkdir data`.
    *   Review any warnings or error messages printed by the `setup.sh` script regarding skipped or failed installations.

### Method 2: Manual Installation

If you prefer to install everything manually or the setup script encounters issues on your specific system:

1.  **Project Directory:**
    Create your project directory and navigate into it:
    ```bash
    mkdir osintelOSINTel-Dashboard
    cd osintelOSINTel-Dashboard
    ```
    Place `app.py`, `data.json`, `history.json` (empty `[]`), and the `templates/index.html` file here.

2.  **Install Prerequisites (System-Wide):**
    Ensure Python 3.8+, pip, venv, git, curl, and other OSINT tools are installed.
    ```bash
    sudo apt update
    sudo apt install -y python3 python3-pip python3-venv git curl whois nmap dnsrecon whatweb libimage-exiftool-perl ffuf
    ```

3.  **Python Virtual Environment:**
    ```bash
    python3 -m venv venv
    source venv/bin/activate
    ```

4.  **Install Core Python Packages (into venv):**
    ```bash
    pip install Flask holehe theHarvester
    ```

5.  **Manually Clone and Set Up Tools:**
    Create a `./tools` directory: `mkdir tools`. Then, for each tool defined in `data.json` that has `"requires_clone": true`:

    *   **Sherlock:**
        ```bash
        cd tools
        git clone https://github.com/sherlock-project/sherlock.git sherlock 
        cd sherlock
        if [ -f sherlock/requirements.txt ]; then pip install -r sherlock/requirements.txt; fi
        cd ../.. 
        ```
        *In `data.json`, ensure:* `"clone_dir": "tools/sherlock"`, `"run_in_directory": "tools/sherlock"`, `"requirements_file": "sherlock/requirements.txt"`.

    *   **Sublist3r:**
        ```bash
        cd tools
        git clone https://github.com/aboul3la/Sublist3r.git Sublist3r
        cd Sublist3r
        if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
        cd ../..
        ```
        *In `data.json`, ensure:* `"clone_dir": "tools/Sublist3r"`, `"run_in_directory": "tools/Sublist3r"`, `"requirements_file": "requirements.txt"`.

    *   **GHunt:**
        ```bash
        cd tools
        git clone https://github.com/mxrch/GHunt.git GHunt
        cd GHunt 
        if [ -f GHunt/requirements.txt ]; then (cd GHunt && pip install -r requirements.txt); fi
        (cd GHunt && python3 check_and_gen_cookies.py) # CRITICAL: Manual cookie generation
        cd ../..
        ```
        *In `data.json`, ensure:* `"clone_dir": "tools/GHunt"`, `"run_in_directory": "tools/GHunt"`, `"requirements_file": "GHunt/requirements.txt"`.

    *   **Metagoofil:**
        ```bash
        cd tools
        git clone https://github.com/laramies/metagoofil.git metagoofil
        cd ../..
        ```
        *In `data.json`, ensure:* `"clone_dir": "tools/metagoofil"`, `"run_in_directory": "tools/metagoofil"`. (Ensure `libimage-exiftool-perl` is installed via `apt`).

    **Note on `data.json` paths:** The `clone_dir` and `run_in_directory` fields in `data.json` tell `app.py` where to find these tools. Ensure they match your manual cloning structure.

6.  **Create `data` Directory:**
    In your project root: `mkdir data`

## Running the Application

1.  **Activate Virtual Environment:**
    If not already active, navigate to your project directory and run:
    ```bash
    source venv/bin/activate
    ```

2.  **Start the Flask Server:**
    ```bash
    python3 app.py
    ```

3.  **Access the Dashboard:**
    The Flask development server, by default in `app.py`, runs on `host='0.0.0.0'` and `port=5001`.
    *   **`0.0.0.0`** means it listens on all available network interfaces on the machine where it's running.
    *   This allows you to access the dashboard from **any other machine on the same local network** by navigating to `http://YOUR_SERVER_IP:5001` (e.g., `http://192.168.1.10:5001`), where `YOUR_SERVER_IP` is the local IP address of the machine running the dashboard.
    *   If you are accessing it from the same machine it's running on, you can use `http://localhost:5001` or `http://127.0.0.1:5001`.
    *   If you only want the dashboard to be accessible from the machine it's running on (localhost only), you can change `host='0.0.0.0'` to `host='localhost'` in the `app.run(...)` line at the bottom of `app.py`.

## Usage

*   **Sidebar:** Select a tool from the list.
*   **Tool Panel:** Input required information.
*   **Run Tool:** Click the "Run Tool" button. Output appears below. URLs are clickable.
*   **Manage Tools:**
    *   **Add New Tool:** Configure name, command template (`{{input_id}}` for placeholders), input fields, output filename pattern, and optional Git cloning.
    *   **Edit/Delete:** Buttons next to each tool.
*   **History:** Click "Hist" next to a tool to view past executions. Click an entry to load its saved output.

## Contributing & Feedback

This project is open source and contributions are welcome! If you have suggestions, bug reports, or want to add new features or tools:

*   **Open an Issue:** Use the GitHub Issues tracker for bugs or feature discussions.
*   **Pull Requests:** Feel free to fork the repository and submit pull requests.


## Troubleshooting

*   **"Command not found" (Nmap, ffuf, etc.):** Ensure the tool is installed globally (`sudo apt install <tool_name>`).
*   **Python errors:** Check Flask server console output. Ensure Python dependencies are in the active virtual environment.
*   **Tool cloning/requirements errors:** Check internet, Git URLs. For nested `requirements.txt`, verify paths.
*   **GHunt not working:** Likely missing/invalid `GHunt/cookies.json`. Re-run `check_and_gen_cookies.py`.
*   **Jinja2 Template Errors:** Avoid active Jinja2 tags `{{ ... }}` in HTML attributes like `placeholder` if they are not meant to be rendered by Flask.
