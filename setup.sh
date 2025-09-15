#!/bin/bash

# Setup Script V1.2

# CAUTION WHEN MODIFYING THIS SCRIPT, it is fully automated, and if using sudo can do system-wide changes, if changed anything without properly caution or study, could harm your PC
skipped_system_tools=""
failed_system_tools=""
skipped_clonable_tools=""
failed_clonable_tools_clone=""
failed_clonable_tools_reqs=""

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

handle_clonable_tool_installation() {
    local tool_name="$1"
    local target_dir="$2"
    local clone_url="$3"
    local install_reqs_cmd="$4"
    local action="clone"

    if [ -d "$target_dir" ]; then
        echo ""
        while true; do
            read -r -p "Directory '$target_dir' for $tool_name already exists. Options: [ri] Reinstall (removes old), [up] Update (git pull), [rm] Remove, [ig] Ignore: " choice
            case "$choice" in
                ri|RI) echo "Removing existing '$target_dir' for $tool_name..."; rm -rf "$target_dir"; action="clone"; break ;;
                up|UP)
                    echo "Attempting to update $tool_name in '$target_dir' using git pull..."
                    if (cd "$target_dir" && git pull); then
                        echo "$tool_name updated successfully via git pull."
                        echo "Checking/Re-installing requirements for $tool_name after update..."
                        if ! eval "$install_reqs_cmd"; then failed_clonable_tools_reqs+="$tool_name, "; fi
                    else
                        echo "Failed to update $tool_name via git pull."
                        failed_clonable_tools_clone+="$tool_name (update failed), "
                    fi
                    action="skip_clone"; break ;;
                rm|RM) echo "Removing existing '$target_dir' for $tool_name and skipping re-clone."; rm -rf "$target_dir"; action="skip"; break ;;
                ig|IG|*) echo "Ignoring existing '$target_dir' for $tool_name, skipping."; action="skip"; break ;;
            esac
        done
    fi

    if [ "$action" == "clone" ]; then
        echo "Cloning $tool_name from $clone_url..."
        if git clone "$clone_url" "$target_dir"; then
            if ! eval "$install_reqs_cmd"; then failed_clonable_tools_reqs+="$tool_name, "; fi
        else
            echo "ERROR: Failed to clone $tool_name."; failed_clonable_tools_clone+="$tool_name, ";
        fi
    elif [ "$action" == "skip" ]; then
        skipped_clonable_tools+="$tool_name, "
    fi
}

echo "--- OSINT Dashboard Setup V1.2 ---"
echo "This script will guide you through installing necessary system packages and OSINT tools."
echo ""

non_script_files=$(find . -maxdepth 1 -not -name "$(basename "$0")" -not -name "." -not -name ".." -not -name ".git*" -not -name ".vscode*" -not -name "venv" -print -quit)

if [ -n "$non_script_files" ]; then
    echo "WARNING: The current directory ($PWD) is not empty."
    read -r -p "Do you want to proceed with the installation in this directory? (y/N): " proceed_in_current
    if [[ ! "$proceed_in_current" =~ ^[Yy]$ ]]; then
        echo "Aborting setup. Please move this script to an empty directory or a dedicated project folder and re-run it from there."
        exit 1
    fi
    echo "Proceeding with installation in the current non-empty directory..."
else
    echo "Current directory appears suitable for a new project setup."
fi
echo ""

VENV_DIR="./venv" 

if [ -n "$VIRTUAL_ENV" ]; then
    echo "INFO: Already inside an active virtual environment: $VIRTUAL_ENV"
    expected_venv_path="$(pwd)/$VENV_DIR"
    if [ "$(cd "$VIRTUAL_ENV" && pwd)" != "$(cd "$expected_venv_path" && pwd)" ]; then
      echo "WARNING: The active venv ($VIRTUAL_ENV) is not the local '$VENV_DIR' in the current project."
      echo "It's recommended to use a local venv for this project."
      read -r -p "Do you want to proceed using the current active venv? (y/N): " use_current_venv
      if [[ ! "$use_current_venv" =~ ^[Yy]$ ]]; then
        echo "Aborting. Please deactivate the current venv or create/activate one in '$VENV_DIR'."
        exit 1
      fi
    fi
else
    echo "INFO: Not currently inside a virtual environment."
    if [ -d "$VENV_DIR" ]; then
        echo "INFO: Virtual environment '$VENV_DIR' found in the current directory."
        echo "Attempting to activate it..."
        source "$VENV_DIR/bin/activate"
        if [ -z "$VIRTUAL_ENV" ] || [ "$(cd "$VIRTUAL_ENV" && pwd)" != "$(cd "$VENV_DIR" && pwd)" ]; then
            echo "ERROR: Failed to activate the existing virtual environment '$VENV_DIR'."
            echo "Please activate it manually ('source $VENV_DIR/bin/activate') and re-run this script."
            exit 1
        else
            echo "Successfully activated existing virtual environment: $VIRTUAL_ENV"
        fi
    else
        echo "INFO: Virtual environment '$VENV_DIR' not found. Attempting to create it..."
        if ! python3 -m venv "$VENV_DIR"; then
            echo "ERROR: Failed to create virtual environment '$VENV_DIR'."
            echo "Please ensure 'python3-venv' package is installed ('sudo apt install python3-venv') and try again."
            exit 1
        fi
        echo "Virtual environment '$VENV_DIR' created. Attempting to activate it..."
        source "$VENV_DIR/bin/activate"
        if [ -z "$VIRTUAL_ENV" ]; then
            echo "ERROR: Failed to activate the newly created virtual environment '$VENV_DIR'."
            echo "Please activate it manually ('source $VENV_DIR/bin/activate') and re-run this script."
            exit 1
        else
            echo "Successfully created and activated virtual environment: $VIRTUAL_ENV"
        fi
    fi
fi
echo ""
echo "INFO: All Python packages (pip install) will be installed into the active virtual environment: $VIRTUAL_ENV"
echo ""

( \
    echo "STEP 1: Updating system packages (sudo password may be required)..." && \
    sudo apt update -y && sudo apt upgrade -y && \
    echo "System package lists updated." && echo "" && \
    
    echo "STEP 2: Installing ESSENTIAL system packages..."
    echo "These are required for basic script operation or by core Python tools."
    echo "Packages to be installed SYSTEM-WIDE via apt: python3-pip, python3-venv (if not already), git, curl."
    essential_pkgs_for_apt=("python3-pip" "python3-venv" "git" "curl")
    if ! sudo apt install -y "${essential_pkgs_for_apt[@]}"; then
        echo "ERROR: Failed to install essential system packages. Aborting."
        exit 1;
    fi
    echo "Essential system packages installed/verified." && echo "" && \

    echo "STEP 3: Optional OSINT System Packages Installation"
    osint_system_tools=(
        "Nmap|nmap|Network exploration tool and security/port scanner."
        "Whois|whois|Client for the WHOIS directory service (domain/IP ownership)."
        "Dnsrecon|dnsrecon|Standard DNS enumeration script (subdomains, records)."
        "WhatWeb|whatweb|Identify technologies used on websites."
        "FFUF|ffuf|Fast web fuzzer (content discovery, directory/file brute-forcing)."
        "ExifTool|libimage-exiftool-perl|Utility for reading and writing meta information in files (used by Metagoofil)."
    )
    echo "The following OPTIONAL OSINT system packages can be installed SYSTEM-WIDE via apt:"
    idx=0
    for tool_entry in "${osint_system_tools[@]}"; do
        IFS='|' read -r display_name pkg_name description <<< "$tool_entry"; idx=$((idx + 1))
        already_installed_msg=""; if command_exists "$pkg_name" || (dpkg -s "$pkg_name" >/dev/null 2>&1); then already_installed_msg=" (already installed)"; fi
        echo "  S$idx) $display_name - $description (Package: $pkg_name)$already_installed_msg"
    done
    echo "  S_all) Install ALL optional OSINT system packages listed above."
    echo "  S_skip) Skip all optional OSINT system packages."
    echo ""
    read -r -p "Your choice for OSINT system packages (e.g., 'S_all', 'S1,S3', 'S_skip'): " sys_choice
    packages_to_install=()
    if [[ "$sys_choice" =~ ^([Ss]_[Aa][Ll][Ll])$ ]]; then
        for tool_entry in "${osint_system_tools[@]}"; do IFS='|' read -r _ pkg_name _ <<< "$tool_entry"; packages_to_install+=("$pkg_name"); done
    elif [[ ! "$sys_choice" =~ ^([Ss]_[Ss][Kk][Ii][Pp])$ ]]; then
        IFS=', ' read -r -a raw_indices <<< "$sys_choice"
        for i in "${raw_indices[@]}"; do
            num_idx=${i#[Ss]}; if [[ "$num_idx" =~ ^[0-9]+$ ]] && [ "$num_idx" -ge 1 ] && [ "$num_idx" -le ${#osint_system_tools[@]} ]; then
                tool_entry="${osint_system_tools[$((num_idx - 1))]}"; IFS='|' read -r _ pkg_name _ <<< "$tool_entry"; packages_to_install+=("$pkg_name")
            else echo "Warning: Invalid system package selection '$i' ignored."; fi
        done
        packages_to_install=($(printf "%s\n" "${packages_to_install[@]}" | sort -u | tr '\n' ' '))
    fi
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        echo "Attempting to install selected system packages: ${packages_to_install[*]}..."
        if ! sudo apt install -y "${packages_to_install[@]}"; then
            echo "ERROR: Failed to install some selected system packages. Please check apt output."
            failed_system_tools+="Selected OSINT system packages (${packages_to_install[*]}), "
        else echo "Selected OSINT system packages installed successfully."; fi
    else
        echo "No optional OSINT system packages selected for installation or S_skip chosen."
        if [[ "$sys_choice" =~ ^([Ss]_[Ss][Kk][Ii][Pp])$ ]]; then
            for tool_entry in "${osint_system_tools[@]}"; do IFS='|' read -r display_name _ _ <<< "$tool_entry"; skipped_system_tools+="$display_name, "; done
        else
            for tool_entry in "${osint_system_tools[@]}"; do
                is_selected=false; IFS='|' read -r current_display_name current_pkg_name _ <<< "$tool_entry"
                for selected_pkg in "${packages_to_install[@]}"; do if [[ "$current_pkg_name" == "$selected_pkg" ]]; then is_selected=true; break; fi; done
                if ! $is_selected; then skipped_system_tools+="$current_display_name, "; fi
            done
        fi
    fi
    echo "OSINT system packages check/installation complete." && echo "" && \

    echo "STEP 4: Installing Core Python Packages into Virtual Environment '$VIRTUAL_ENV'..."
    echo "Packages: Flask, holehe, theHarvester." && \
    if ! pip install Flask holehe theHarvester; then
        echo "ERROR: Failed to install core Python packages into venv. Please check pip output."
    fi && \
    echo "Core Python packages installed into venv." && echo "" && \

    echo "STEP 5: Clonable Tools Installation/Update (into Virtual Environment if Python-based)"
    mkdir -p ./tools
    clonable_tools=(
        "Sherlock (Username searching)|./tools/sherlock|https://github.com/sherlock-project/sherlock.git|if [ -f sherlock/requirements.txt ]; then pip install -r sherlock/requirements.txt; else echo 'No requirements.txt at sherlock/ for Sherlock.' && failed_clonable_tools_reqs+='Sherlock, '; fi"
        "Sublist3r (Subdomain enumeration)|./tools/Sublist3r|https://github.com/aboul3la/Sublist3r.git|if [ -f requirements.txt ]; then pip install -r requirements.txt; else echo 'No requirements.txt for Sublist3r.' && failed_clonable_tools_reqs+='Sublist3r, '; fi"
        "GHunt (Google Account investigation)|./tools/GHunt|https://github.com/mxrch/GHunt.git|if [ -f GHunt/requirements.txt ]; then pip install -r GHunt/requirements.txt; else echo 'No requirements.txt at GHunt/ for GHunt.' && failed_clonable_tools_reqs+='GHunt, '; fi"
        "Metagoofil (Metadata extraction)|./tools/metagoofil|https://github.com/laramies/metagoofil.git|echo 'Metagoofil typically does not have a pip requirements.txt.'"
    )
    echo "The following CLONABLE tools can be installed/updated from GitHub (Python dependencies go into '$VIRTUAL_ENV'):"
    idx=0
    for tool_entry in "${clonable_tools[@]}"; do
        IFS='|' read -r display_name_desc _ _ _ <<< "$tool_entry"; idx=$((idx + 1))
        echo "  C$idx) $display_name_desc"
    done
    echo "  C_all) Install/Update ALL clonable tools listed above."
    echo "  C_skip) Skip all clonable tools."
    echo ""
    read -r -p "Your choice for clonable tools (e.g., 'C_all', 'C1,C3', 'C_skip'): " clone_choice
    selected_clone_indices=()
    if [[ "$clone_choice" =~ ^([Cc]_[Aa][Ll][Ll])$ ]]; then 
        for i in $(seq 1 ${#clonable_tools[@]}); do selected_clone_indices+=($((i - 1))); done
    elif [[ ! "$clone_choice" =~ ^([Cc]_[Ss][Kk][Ii][Pp])$ ]]; then
        IFS=', ' read -r -a raw_indices <<< "$clone_choice"
        for i in "${raw_indices[@]}"; do
            num_idx=${i#[Cc]}; if [[ "$num_idx" =~ ^[0-9]+$ ]] && [ "$num_idx" -ge 1 ] && [ "$num_idx" -le ${#clonable_tools[@]} ]; then
                selected_clone_indices+=($((num_idx - 1)))
            else echo "Warning: Invalid clonable tool selection '$i' ignored."; fi
        done
        selected_clone_indices=($(printf "%s\n" "${selected_clone_indices[@]}" | sort -u | tr '\n' ' '))
    fi
    if [ ${#selected_clone_indices[@]} -gt 0 ]; then
        echo ""
        for index in "${selected_clone_indices[@]}"; do
            tool_entry="${clonable_tools[$index]}"; IFS='|' read -r display_name_desc target_dir clone_url reqs_cmd_template <<< "$tool_entry"
            display_name=$(echo "$display_name_desc" | awk -F'(' '{print $1}' | sed 's/ *$//')
            full_clone_cmd="git clone $clone_url $target_dir"; full_reqs_cmd="(cd $target_dir && $reqs_cmd_template)"
            handle_clonable_tool_installation "$display_name" "$target_dir" "$clone_url" "$full_reqs_cmd"
        done
    else
        echo "No clonable tools selected for installation or C_skip chosen."
         if [[ "$clone_choice" =~ ^([Cc]_[Ss][Kk][Ii][Pp])$ ]]; then
            for tool_entry in "${clonable_tools[@]}"; do
                IFS='|' read -r display_name_desc _ _ _ <<< "$tool_entry"
                display_name=$(echo "$display_name_desc" | awk -F'(' '{print $1}' | sed 's/ *$//')
                skipped_clonable_tools+="$display_name, "
            done
        fi
    fi
    echo "Clonable tools processing complete." && echo "" && \
    

    echo "" && \
    echo "------------------------------------------------------------------------------------" && \
    echo "SETUP SCRIPT V1.2 - FINISHED." && \
    echo "" && \
    echo "SUMMARY & ATTENTION REQUIRED:" && \
    echo "" && \
    ([ -n "$skipped_system_tools" ] || [ -n "$failed_system_tools" ] || [ -n "$skipped_clonable_tools" ] || [ -n "$failed_clonable_tools_clone" ] || [ -n "$failed_clonable_tools_reqs" ]) && \
    echo "Please review the following:"

    if [ -n "$skipped_system_tools" ]; then
        echo "  - SKIPPED Optional System Packages (User choice or default): ${skipped_system_tools%, }"
        echo "    Functionality relying on these tools may be unavailable. Install manually if needed (e.g., 'sudo apt install <package_name>')."
    fi
    if [ -n "$failed_system_tools" ]; then
        echo "  - FAILED System Package Installations: ${failed_system_tools%, }"
        echo "    Please check 'apt' output above for errors and try manual installation."
    fi
    if [ -n "$skipped_clonable_tools" ]; then
        echo "  - SKIPPED Clonable Tools (User choice or existing dir ignored): ${skipped_clonable_tools%, }"
        echo "    These tools are not installed/updated. Corresponding dashboard features will not work."
    fi
    if [ -n "$failed_clonable_tools_clone" ]; then
        echo "  - FAILED Tool Clones: ${failed_clonable_tools_clone%, }"
        echo "    Check network connection or Git URLs. Manual cloning might be required."
    fi
    if [ -n "$failed_clonable_tools_reqs" ]; then
        echo "  - FAILED/SKIPPED Python Requirements for Cloned Tools: ${failed_clonable_tools_reqs%, }"
        echo "    These tools might not run correctly. Check their directories for 'requirements.txt' and install manually (e.g., 'pip install -r path/to/requirements.txt')."
    fi
    if ! ([ -n "$skipped_system_tools" ] || [ -n "$failed_system_tools" ] || [ -n "$skipped_clonable_tools" ] || [ -n "$failed_clonable_tools_clone" ] || [ -n "$failed_clonable_tools_reqs" ]); then
      echo "  All selected installations and checks seem to have proceeded without major issues noted by the script."
      echo "  However, always verify functionality."
    fi
    echo "" && \

    echo "NEXT STEPS & VERIFICATIONS:" && \
    echo "1. Ensure app.py, data.json, history.json, and templates/index.html are in this directory ($PWD)." && \
    echo "2. The 'data' and 'tools' directories should exist here. The 'data' directory was created if missing." && \
    echo "" && \
    echo "3. IMPORTANT FOR GHUNT (if installed/updated):" && \
    echo "   Navigate to './tools/GHunt/GHunt/' (or where GHunt's main scripts are) and manually run:" && \
    echo "   'python3 check_and_gen_cookies.py' to generate cookies." && \
    echo "" && \
    echo "4. IMPORTANT FOR data.json:" && \
    echo "   Verify that 'clone_dir' and 'run_in_directory' paths in your data.json for all cloned tools" && \
    echo "   match the actual cloned locations (e.g., 'tools/sherlock', 'tools/Sublist3r', etc.)." && \
    echo "" && \
    echo "THIS IS JUST A HELPER SCRIPT. ERRORS CAN OCCUR." && \
    echo "MAKE SURE TO CHECK EVERYTHING: locations of cloned folders, tool functionality," && \
    echo "and ensure all tools function as expected from the web dashboard." && \
    echo "" && \
    echo "FINAL CONSIDERATION:" && \
    echo "Now follow the steps above or just try running 'python3 app.py' (ensure venv is active: 'source $VENV_DIR/bin/activate')." && \
    echo "Make sure to check the IP address the Flask app runs on (usually 0.0.0.0:5001, accessible via your server's IP)," && \
    echo "or change it to 'localhost:5001' in app.py if you only want local access." && \
    echo "------------------------------------------------------------------------------------" \

) || echo "A critical error occurred during the main setup process, and the script was exited."