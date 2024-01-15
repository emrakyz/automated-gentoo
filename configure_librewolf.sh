#!/bin/bash

URL_USER_JS="https://raw.githubusercontent.com/arkenfox/user.js/master/user.js"
URL_UPDATER_SH="https://raw.githubusercontent.com/arkenfox/user.js/master/updater.sh"
URL_USER_OVERRIDES_JS="https://raw.githubusercontent.com/emrakyz/dotfiles/main/user-overrides.js"
URL_USERCHROME_CSS="https://raw.githubusercontent.com/emrakyz/dotfiles/main/userChrome.css"
URL_USERCONTENT_CSS="https://raw.githubusercontent.com/emrakyz/dotfiles/main/userContent.css"
URL_UBLOCK_BACKUP="https://raw.githubusercontent.com/emrakyz/dotfiles/main/ublock_backup.txt"

FILES_DIR="$HOME/files"

USERNAME="$(echo $HOME | sed 's|/home/||')"

# Fail Fast & Fail Safe on errors and stop.
set -Eeo pipefail

# Custom logging function for better readability.
log_info() {
        sleep "0.3"

        case "${1}" in
                g) COLOR="${GREEN}" MESSAGE="DONE!" ;;
                r) COLOR="${RED}" MESSAGE="WARNING!" ;;
                b) COLOR="${BLUE}" MESSAGE="STARTING." ;;
                c) COLOR="${BLUE}" MESSAGE="RUNNING." ;;
        esac

        COLORED_TASK_INFO="${WHITE}(${CYAN}${TASK_NUMBER}${PURPLE}/${CYAN}${TOTAL_TASKS}${WHITE})"
        MESSAGE_WITHOUT_TASK_NUMBER="${2}"

        DATE="$(date "+%Y-%m-%d ${CYAN}/${PURPLE} %H:%M:%S")"

        FULL_LOG="${CYAN}[${PURPLE}${DATE}${CYAN}] ${YELLOW}>>>${COLOR}${MESSAGE}${YELLOW}<<< ${COLORED_TASK_INFO} - ${COLOR}${MESSAGE_WITHOUT_TASK_NUMBER}${NC}"

        { [[ "${1}" == "c" ]] && echo -e "\n\n${FULL_LOG}"; } || echo -e "${FULL_LOG}"
}

# Error handler function. This will show which command failed.
handle_error () {
    error_status=$?
    command_line=${BASH_COMMAND}
    error_line=${BASH_LINENO[0]}
    log_info "$(date '+%Y-%m-%d %H:%M:%S') Error on line $error_line: command '${command_line}' exited with status: $error_status" |
    tee -a error.log.txt
}

trap 'handle_error' ERR
trap 'handle_error' RETURN

# File Associations with URL, Download Location, and Final Destination.
declare -A associate_files

associate_f() {
    local key="${1}"
    local url="${2}"
    local base_path="${3}"

    # Constructing the final path by appending the key to the base path.
    local final_path="${base_path}/${key}"

    associate_files["${key}"]="${url} ${FILES_DIR}/${key} ${final_path}"
}

# Set file associations. Updating could be singular but there is no need
# since it's instant and not problematic.
update_associations() {
    associate_f "user.js" "${URL_USER_JS}" "${LIBREW_PROF_DIR}"
    associate_f "updater.sh" "${URL_UPDATER_SH}" "${LIBREW_PROF_DIR}"
    associate_f "user-overrides.js" "${URL_USER_OVERRIDES_JS}" "${LIBREW_PROF_DIR}"
    associate_f "userChrome.css" "${URL_USERCHROME_CSS}" "${LIBREW_CHROME_DIR}"
    associate_f "userContent.css" "${URL_USERCONTENT_CSS}" "${LIBREW_CHROME_DIR}"
    associate_f "ublock_backup.txt" "${URL_UBLOCK_BACKUP}" "${HOME}"
}

update_associations

move_file() {
    local key="${1}"
    local custom_destination="${2:-}"  # Optional custom destination.
    local download_path final_destination
    IFS=' ' read -r _ download_path final_destination <<< "${associate_files[${key}]}"

    # Move the file.
    mv "${download_path}" "${final_destination}"
}

# Display the progress bar.
update_progress() {
    local total="${1}"
    local current="${2}"
    local pct="$(( (current * 100) / total ))"

    # Clear the line and display the progress bar.
    printf "\rProgress: [%-100s] %d%%" "$(printf "%-${pct}s" | tr ' ' '#')" "$pct"
}

# Determine and handle download type.
download_file() {
    local source="${1}"
    local dest="${2}"

    # Check for file existence and skip downloading if it exists.
    [ -f "${dest}" ] && {
        log_info "File ${dest} already exists, skipping download."
        return
    }

    # Handling regular file URLs.
    curl -L "${source}" -o "${dest}" > "/dev/null" 2>&1
}

# Function to Retrieve All Files with Progress Bar.
retrieve_files() {
    mkdir -p "${FILES_DIR}"
    local total="$((${#associate_files[@]}))"
    local current="0"

    for key in "${!associate_files[@]}"; do
        current="$((current + 1))"
        update_progress "${total}" "${current}"

        IFS=' ' read -r source dest _ <<< "${associate_files[${key}]}"
        download_file "${source}" "${dest}"
    done
}

start_process() {
    # Start librewolf in headless mode in order to create config directory for it.
    librewolf --headless > "/dev/null" 2>&1 &
    sleep "3"
    killall "librewolf"

    # Find the profile folder.
    LIBREW_CONFIG_DIR="${HOME}/.librewolf"
    LIBREW_PROF_NAME="$(sed -n "/Default=.*.default-release/ s/.*=//p" "${LIBREW_CONFIG_DIR}/profiles.ini")"
    LIBREW_PROF_DIR="${LIBREW_CONFIG_DIR}/${LIBREW_PROF_NAME}"
    LIBREW_CHROME_DIR="${LIBREW_PROF_DIR}/chrome"

    # userChrome.css and userContent.css files need to be placed in the chrome dir.
    mkdir -p "${LIBREW_CHROME_DIR}"

    # Since we have new variables, renew the associations in order to move files properly.
    update_associations

    # Move the Librewolf configuration files.
    move_file "user.js"
    move_file "user-overrides.js"
    move_file "updater.sh"
    move_file "userChrome.css"
    move_file "userContent.css"

    # We need to make Arkenfox.js script executable.
    # And the user needs to own the .librewolf directory.
    chmod +x "${LIBREW_PROF_DIR}/updater.sh"
    doas chown -R "${USERNAME}":"${USERNAME}" "${HOME}"

    # Run the Arkenfox.js script to apply the configuration files.
    "${LIBREW_PROF_DIR}/updater.sh" -s -u

    # Create the directory for the extensions.
    EXT_DIR="${LIBREW_PROF_DIR}/extensions"
    mkdir -p "${EXT_DIR}"

    # These are the extensions we want to download.
    ADDON_NAMES=("ublock-origin" "istilldontcareaboutcookies" "vimium-ff" "minimalist-open-in-mpv" "load-reddit-images-directly")

    # For loop to download, extract, modify and move all extension properly.
    # Loop all listed addons.
    for ADDON_NAME in "${ADDON_NAMES[@]}"
    do
        # We first find the addon URL, curl it and then find the proper download link.
        ADDON_URL="$(curl --silent "https://addons.mozilla.org/en-US/firefox/addon/${ADDON_NAME}/" |
    		   grep -o 'https://addons.mozilla.org/firefox/downloads/file/[^"]*')"

    	# We download the extension file with the extension.xpi name.
    	curl -sL "${ADDON_URL}" -o "extension.xpi"

    	# We unzip the files and search for the extension ID since librewolf
    	# Requires the ID  in the name. We also manipulate the text to make it
    	# usable.
    	EXT_ID="$(unzip -p "extension.xpi" "manifest.json" | grep "\"id\"")"
    	EXT_ID="${EXT_ID%\"*}"
    	EXT_ID="${EXT_ID##*\"}"

    	# We move the extension file to its proper location by naming it with
    	# its extension ID.
    	mv extension.xpi "${EXT_DIR}/${EXT_ID}.xpi"
    done

    # Move the ublock setting backup in order to use later.
    move_file "ublock_backup.txt"
}

main() {
    log_info "Retrieving the configuration files..."
    retrieve_files
    log_info "All files have ben retrieved."

    log_info "Starting the process..."
    start_process
    log_info "The process has finished successfully."
    log_info "Librewolf is ready!"
}

main
