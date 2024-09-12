#!/usr/bin/env bash

set -Eeo pipefail

[ "${UID}" = "0" ] && echo "Root not allowed" && exit

G='\e[1;92m' R='\e[1;91m' B='\e[1;94m'
P='\e[1;95m' Y='\e[1;93m' N='\033[0m'
C='\e[1;96m' W='\e[1;97m'

URL_USER_JS="https://raw.githubusercontent.com/arkenfox/user.js/master/user.js"
URL_UPDATER_SH="https://raw.githubusercontent.com/arkenfox/user.js/master/updater.sh"
URL_USER_OVERRIDES_JS="https://raw.githubusercontent.com/emrakyz/dotfiles/main/user-overrides.js"
URL_USERCHROME_CSS="https://raw.githubusercontent.com/emrakyz/dotfiles/main/userChrome.css"
URL_USERCONTENT_CSS="https://raw.githubusercontent.com/emrakyz/dotfiles/main/userContent.css"
URL_UBLOCK_BACKUP="https://raw.githubusercontent.com/emrakyz/dotfiles/main/ublock_backup.txt"
URL_BYPASS_PAYWALLS="https://github.com/bpc-clone/bpc_updates/releases/download/latest/bypass_paywalls_clean-3.7.4.0.xpi"

FILES_DIR="${HOME}/files"
USERNAME="$(id -nu "1000")"

loginf() {
        sleep "0.3"

        case "${1}" in
                g) COL="${G}" MSG="DONE!" ;;
                r) COL="${R}" MSG="WARNING!" ;;
                b) COL="${B}" MSG="STARTING." ;;
                c) COL="${B}" MSG="RUNNING." ;;
        esac

        TSK="${W}(${C}${TSKNO}${P}/${C}${ALLTSK}${W})"
        RAWMSG="${2}"

        DATE="$(date "+%Y-%m-%d ${C}/${P} %H:%M:%S")"

        LOG="${C}[${P}${DATE}${C}] ${Y}>>>${COL}${MSG}${Y}<<< ${TSK} - ${COL}${RAWMSG}${N}"

        [ "${1}" = "c" ] && echo -e "\n\n${LOG}" || echo -e "${LOG}"
}

handle_err() {
        stat="${?}"
        cmd="${BASH_COMMAND}"
        line="${LINENO}"
        loginf r "Line ${B}${line}${R}: cmd ${B}'${cmd}'${R} exited with ${B}\"${stat}\""
}

declare -A associate_files

associate_f() {
        key="${1}"
        url="${2}"
        base_path="${3}"

        final_path="${base_path}/${key}"

        associate_files["${key}"]="${url} ${FILES_DIR}/${key} ${final_path}"
}

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
        #local custom_destination="${2:-}"
        local download_path final_destination
        IFS=' ' read -r _ download_path final_destination <<< "${associate_files[${key}]}"

        mv -fv "${download_path}" "${final_destination}"
}

progs() {
        pct="$((100 * ${2} / ${1}))"
        fll="$((65 * pct / 100))"
        bar=""
        for _ in $(seq "1" "${fll}"); do bar="${bar}${G}#${N}"; done
        for _ in $(seq "$((fll + 1))" "65"); do bar="${bar}${R}-${N}"; done
        printf "${bar}${P} ${pct}%%${N}\r"
}

download_file() {
        local source="${1}"
        local dest="${2}"

        [ -f "${dest}" ] && {
                loginf b "File ${dest} already exists, skipping download."
                return
        }

        curl -fSLk "${source}" -o "${dest}" > "/dev/null" 2>&1
}

retrieve_files() {
        rm -rfv "${FILES_DIR}" "${HOME}/ublock_backup.txt"
        mkdir -p "${FILES_DIR}"
        local total="$((${#associate_files[@]}))"
        local current="0"

        for key in "${!associate_files[@]}"; do
                current="$((current + 1))"
                progs "${total}" "${current}"

                IFS=' ' read -r source dest _ <<< "${associate_files[${key}]}"
                download_file "${source}" "${dest}"
        done

        echo ""
}

create_profile() {
        rm -rfv "${HOME}/.librewolf"
        librewolf --headless > "/dev/null" 2>&1 &
        sleep "3"

        killall "librewolf"
}

initiate_vars() {
        LIBREW_CONFIG_DIR="${HOME}/.librewolf"

        LIBREW_PROF_NAME="$(sed -n "/Default=.*\(esr\|release\)$/ { s/Default=//p; q }" \
                "${LIBREW_CONFIG_DIR}/profiles.ini")"

        LIBREW_PROF_DIR="${LIBREW_CONFIG_DIR}/${LIBREW_PROF_NAME}"
        LIBREW_CHROME_DIR="${LIBREW_PROF_DIR}/chrome"

        mkdir -pv "${LIBREW_CHROME_DIR}"

        update_associations
}

place_files() {
        move_file "user.js"
        move_file "user-overrides.js"
        move_file "updater.sh"
        move_file "userChrome.css"
        move_file "userContent.css"
}

modify_orides() {
        sed -i "s|/home/.*/downloads|/home/${USERNAME}/downloads|
		s/Count.*/Count\", $(nproc);/" \
                "${LIBREW_PROF_DIR}/user-overrides.js"
}

run_arkenfox() {
        chmod +x "${LIBREW_PROF_DIR}/updater.sh"
        doas chown -R "1000":"1000" "${HOME}"

        "${LIBREW_PROF_DIR}/updater.sh" -s -u
}

install_extensions() {
        EXT_DIR="${LIBREW_PROF_DIR}/extensions"
        mkdir -pv "${EXT_DIR}"

        ADDON_NAMES=("ublock-origin" "istilldontcareaboutcookies"
                "vimium-ff" "load-reddit-images-directly"
                "dark-background-light-text" "sponsorblock" "dearrow")

        for ADDON_NAME in "${ADDON_NAMES[@]}"; do
                ADDON_URL="$(curl -fSk "https://addons.mozilla.org/en-US/firefox/addon/${ADDON_NAME}/" |
                        grep -o 'https://addons.mozilla.org/firefox/downloads/file/[^"]*')"

                curl -fSLk "${ADDON_URL}" -o "extension.xpi"

                EXT_ID="$(unzip -p "extension.xpi" "manifest.json" | grep "\"id\"")"
                EXT_ID="${EXT_ID%\"*}"
                EXT_ID="${EXT_ID##*\"}"

                mv -fv "extension.xpi" "${EXT_DIR}/${EXT_ID}.xpi"
        done
}

install_bypass_paywalls() {
        curl -fSLk "${URL_BYPASS_PAYWALLS}" -o "extension.xpi"

        EXT_ID="$(unzip -p "extension.xpi" "manifest.json" | grep "\"id\"")"
        EXT_ID="${EXT_ID%\"*}"
        EXT_ID="${EXT_ID##*\"}"

        mv -fv "extension.xpi" "${EXT_DIR}/${EXT_ID}.xpi"
}

place_ublock_backup() {
        move_file "ublock_backup.txt"
        rm -rfv "${HOME}/files"
}

main() {
        declare -A tsks
        tsks["retrieve_files"]="Retrieve the files.
		        Files retrieved."

        tsks["create_profile"]="Create a profile.
		           A profile created."

        tsks["initiate_vars"]="Initiate new variables.
		             New variabeles initiated."

        tsks["place_files"]="Place the necessary files.
			The necessary files placed."

        tsks["modify_orides"]="Modify overrides.
			Overrides modified."

        tsks["run_arkenfox"]="Run the ArkenFox script.
                                 The Arkenfox script successful."

        tsks["install_extensions"]="Install browser extensions.
                                 Browser extensions installed."

        tsks["install_bypass_paywalls"]="Install bypass_paywalls_clean.
                                 bypass_paywalls_clean installed."

        tsks["place_ublock_backup"]="Place uBlock Backup.
                                uBlock Backup placed."

        tsk_ord=("retrieve_files" "create_profile" "initiate_vars" "place_files" "modify_orides"
                "run_arkenfox" "install_extensions" "install_bypass_paywalls" "place_ublock_backup")

        ALLTSK="${#tsks[@]}"
        TSKNO="1"

        trap 'handle_err' ERR RETURN

        for funct in "${tsk_ord[@]}"; do
                descript="${tsks[${funct}]}"
                descript="${descript%%$'\n'*}"

                msgdone="$(echo "${tsks[${funct}]}" | tail -n "1" | sed 's/^[[:space:]]*//g')"

                loginf b "${descript}"

                "${funct}"
                loginf g "${msgdone}"

                [[ "${TSKNO}" -eq "${ALLTSK}" ]] && {
                        loginf g "All tsks completed."
                        kill "0" > "/dev/null"
                }

                ((TSKNO++))
        done
}

main
