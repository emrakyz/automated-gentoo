#!/usr/bin/env bash

[[ "${UID}" == "0" ]] || {
        echo "Root login required"
        exit
}

set -Eeo pipefail

G='\e[1;92m' R='\e[1;91m' B='\e[1;94m'
P='\e[1;95m' Y='\e[1;93m' N='\033[0m'
C='\e[1;96m' W='\e[1;97m'

cleanup_logs() {
        [[ -f "logfile.txt" ]] && {
                sed -E -i 's/\r//g
			s/.*RUNNING.*//g' "logfile.txt"

                sed -i -e :a -e '/^\n*$/N; /^\n$/D; ta' "logfile.txt"
                sed -i '/\x1b\[K$/d' "logfile.txt"
                sed -i -e :a -e '/^\n*$/N; /^\n$/D; ta' "logfile.txt"
        }
}

loginf() {
        sleep "0.2"

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

confirm_action() {
        while true; do
                echo -en "${G}Do you confirm? (y/n): ${N}"
                read -r user_input

                [[ "${user_input}" =~ ^[yY](es)?$|^[nN]o?$ ]] && break

                echo -e "${R}Invalid selection. Choose one of y, Yes, n, No.${N}"
        done

        [[ "${user_input}" =~ ^[yY](es)?$ ]] && return "0" || return "1"
}

handle_disk() {
        echo -e "${W}Disk operations are extremely critical."
        echo -e "The script can handle proper disk preparation automatically."
        echo -e "You can select your disk and the script will do everything needed."
        echo -e "This process is only valid if you confirm."
        echo -e "If you want to continue by automatic disk preparation then type: ${R}DELETE_EVERYTHING${W}"
        echo -e "If you have done it yourself or prefer manually doing it then type: ${R}SKIP${W}"
        echo -e "The script will later check if you have proper BOOT and ROOT partitions."
        echo -e "After ${R}DELETE_EVERYTHING${W} you will enter your preferred disk device to WIPE."
        echo -e "Type ${R}DELETE_EVERYTHING${W} or ${R}SKIP ${C}"
        echo -en "Type here: "

        read -r INPUT

        echo -e "${N}"

        [[ "${INPUT}" == "DELETE_EVERYTHING" ]] && {
                IFS=$'\n'
                for i in $(lsblk -lnfo NAME,FSTYPE,SIZE); do
                        i="/dev/${i}" &&
                                [[ ! "${i}" =~ ^[^\ ]*[a-mo-z][0-9][[:space:]] ]] &&
                                BLOCK_DEVICES+=("${i}")
                done
                unset IFS

                while true; do
                        for i in "${!BLOCK_DEVICES[@]}"; do
                                echo -e "${P}$((i + 1))) ${Y}${BLOCK_DEVICES[i]}${N}"
                        done

                        echo -ne "${W}Enter the device of your choice: ${C}"

                        read -r SELECTED_DEVICE && CHOSEN_DEVICE="${BLOCK_DEVICES[SELECTED_DEVICE - 1]}"

                        CHOSEN_DEVICE="${CHOSEN_DEVICE%% *}"
                        echo -e "${G}The chosen device is ${CHOSEN_DEVICE}"

                        confirm_action && break

                        echo -e "${R}Declined. Restarting the process...${N}"
                done

                echo -e "${N}"

                {
                        parted -s "${CHOSEN_DEVICE}" print | sed -n 's/^ *\([0-9]\) .*/\1/p' |
                                while read -r part; do
                                        parted -s "${CHOSEN_DEVICE}" rm "${part}"
                                done
                } || true

                parted -s "${CHOSEN_DEVICE}" mklabel gpt
                parted -s "${CHOSEN_DEVICE}" mkpart "efi" fat32 1MiB 250MiB
                parted -s "${CHOSEN_DEVICE}" set 1 esp on

                BOOT_PARTITION="$(lsblk "${CHOSEN_DEVICE}" -lnfo NAME | sed -n 's|^|/dev/|; 2p')"

                mkfs.vfat -F 32 "${BOOT_PARTITION}"

                echo -e "${W}Enter the size for the ROOT partition."
                echo -e "Leave it empty to use all of the rest."

                while true; do
                        echo -en "${G}Size (e.g 100G): ${C}"
                        read -r selected_size

                        [[ -z "${selected_size}" ]] && {
                                CHOSEN_SIZE="100%"
                                echo -e "${G}You have selected to use all of the remaining space."
                                confirm_action && echo ""
                                break
                        }

                        [[ "${selected_size}" =~ ^[1-9][0-9]*[GM]?i?B?$ ]] && {
                                size="${selected_size%%[GMiB]*}"
                                [[ "${selected_size}" =~ [Gg] ]] && size="$((size * 1000))"

                                [[ "${size}" -ge "24000" ]] && {
                                        CHOSEN_SIZE="${selected_size}"
                                        echo -e "${G}You have selected a partition size of ${CHOSEN_SIZE}."
                                        confirm_action && echo ""
                                        break || {
                                                echo -e "${R}Declined. Restarting the process...${N}" && continue
                                        }
                                }
                        }

                        echo -e "${R}Invalid format. Please use formats like 20G, 500M, 1GiB, etc."
                        echo -e "It should at least be 24G or 24GiB or 24000M or 24000MiB"
                done

                parted -s "${CHOSEN_DEVICE}" mkpart "linux" 250MiB "${CHOSEN_SIZE}"
                parted -s "${CHOSEN_DEVICE}" type "2" "0fc63daf-8483-4772-8e79-3d69d8477de4"

                echo -e "${W}Select a file system format for ROOT:${N}"
                echo -e "${W}F2FS is recommended for SSDs and EXT4 for others.${N}"

                while true; do
                        FS_TYPES=("f2fs" "ext4")

                        for i in "${!FS_TYPES[@]}"; do
                                echo -e "${P}$((i + 1))) ${Y}${FS_TYPES[i]}${N}"
                        done

                        echo -ne "${W}Enter the number of your choice: ${C}"

                        read -r SELECTED_FS_TYPE && CHOSEN_FS="${FS_TYPES[SELECTED_FS_TYPE - 1]}"

                        [[ -z "${CHOSEN_FS}" ]] || {
                                echo -e "${G}You have selected ${CHOSEN_FS} file system for ROOT."
                        } || {
                                echo -e "${R}Invalid selection. Please select a valid number."
                                continue
                        }

                        confirm_action && break || echo -e "${R}Declined. Restarting the process...${N}"
                done

                ROOT_PARTITION="$(lsblk "${CHOSEN_DEVICE}" -lnfo NAME | sed -n 's/^/\/dev\//; 3p')"

                [[ "${CHOSEN_FS}" == "f2fs" ]] && {
                        mkfs.f2fs -a "1" \
                                -d "0" \
                                -f \
                                -i \
                                -s "1" \
                                -t "1" \
                                -w "4096" \
                                -z "1" \
                                "${ROOT_PARTITION}"
                } || mkfs.ext4 "${ROOT_PARTITION}"
        } || echo -e "${B}Skipping disk handling...${N}"
}

select_profile() {
        AVAILABLE_PROFILES=("stage3-amd64-musl-llvm"
                "stage3-amd64-nomultilib-openrc"
                "stage3-amd64-openrc")

        while true; do
                echo -e "${W}Select a Gentoo profile:${N}"

                for i in "${!AVAILABLE_PROFILES[@]}"; do
                        echo -e "${P}$((i + 1))) ${Y}${AVAILABLE_PROFILES[i]}${N}"
                done

                echo -ne "${W}Enter the number of your choice: ${C}"
                read -r profile_choice && PROFILE="${AVAILABLE_PROFILES[profile_choice - 1]}"

                [[ -z "${PROFILE}" ]] && {
                        echo -e "${R}Invalid selection. Resetting...${N}"
                        continue
                }

                echo ""

                echo -e "${G}Selected profile: ${PROFILE}${N}"
                confirm_action && break || echo -e "${R}Declined. Resetting...${N}"
                continue
        done
}

find_tarball_url() {
        URL_GENTOO_WEBSITE="https://www.gentoo.org/downloads/"
        URL_GENTOO_TARBALL="$(curl "${URL_GENTOO_WEBSITE}" | sed -n 's/.*href="\([^"]*'"${PROFILE}"'-[^"]*\.tar\.xz\)".*/\1/p')"
        echo ""
        echo -e "${W}The URL:${C} ${URL_GENTOO_TARBALL}${N}"
        echo ""
}

detect_root_part() {
        IFS=$'\n'
        for i in $(lsblk -lnfo NAME,FSTYPE,SIZE); do
                [[ ! "${i%% *}" =~ [a-z]$ ]] &&
                        i="/dev/${i}" &&
                        [[ "${i}" =~ .*(f2fs|ext4).* ]] &&
                        [[ ! "${i%% *}" =~ ^.*n[0-9]$ ]] &&
                        [[ ! "${i}" =~ ^[^\ ]+[\ ]+[^\ ]+$ ]] &&
                        partitions+=("${i}")
        done
        unset IFS

        [ "${!partitions[*]}" ] || {
                loginf r "You do not have any eligible partition for ROOT."
                loginf r "Boot partition should be formatted with vfat FAT32."
                loginf r "Root partition should be formatted with ext4 or f2fs."
                exit "1"
        }

        for i in "${!partitions[@]}"; do
                echo -e "${P}$((i + 1))) ${Y}${partitions[i]}${N}"
        done

        echo -ne "${W}Select your preferred ROOT partition: ${C}"
        read -r partition_choice

        partition_info="${partitions[partition_choice - 1]}"
        PARTITION_ROOT="${partition_info%% *}"

        echo -e "The selected ROOT partition is ${PARTITION_ROOT} ${N}"
        read -rp "Do you want to proceed?: " CONFIRMATION

        [[ "${CONFIRMATION}" =~ [yY](es)? ]] || {
                loginf r "The user has not confirmed the selection."
                exit "1"
        }
}

mount_root_part() {
        mkdir --parents "/mnt/gentoo"
        mount "${PARTITION_ROOT}" "/mnt/gentoo"
}

retrieve_tarball() {
        wget -P "/mnt/gentoo" "${URL_GENTOO_TARBALL}"
}

extract_tarball() {
        tar xpf /mnt/gentoo/stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C "/mnt/gentoo"
}

remove_tarball() {
        rm -rfv "/mnt/gentoo/"stage3-*.tar.xz
}

create_repos_conf() {
        mkdir -pv "/mnt/gentoo/etc/portage/repos.conf"
        cp -fv "/mnt/gentoo/usr/share/portage/config/repos.conf" "/mnt/gentoo/etc/portage/repos.conf/gentoo.conf"
}

create_resolv_conf() {
        cp -fv -L "/etc/resolv.conf" "/mnt/gentoo/etc"
}

prepare_chroot() {
        mount --types "proc" "/proc" "/mnt/gentoo/proc"
        mount --rbind "/sys" "/mnt/gentoo/sys"
        mount --make-rslave "/mnt/gentoo/sys"
        mount --rbind "/dev" "/mnt/gentoo/dev"
        mount --make-rslave "/mnt/gentoo/dev"
        mount --bind "/run" "/mnt/gentoo/run"
        mount --make-slave "/mnt/gentoo/run"
}

main() {
        declare -A tsks
        tsks["handle_disk"]="Prepare the disk.
		        The disk prepared."

        tsks["select_profile"]="Select a profile.
		           The profile selected."

        tsks["find_tarball_url"]="Find the Gentoo Tarball URL.
		             The Gentoo Tarball URL found."

        tsks["detect_root_partition"]="Detect and Choose Partition.
			          Partition Chosen."

        tsks["mount_root_partition"]="Mount the root partition.
                                 Root partition mounted."

        tsks["retrieve_tarball"]="Retrieve the Gentoo Tarball.
                                 Gentoo Tarball retrieved."

        tsks["extract_tarball"]="Extract the Gentoo Tarball.
                                Gentoo Tarball extracted."

        tsks["remove_tarball"]="Remove the Gentoo Tarball.
                               Gentoo Tarball removed."

        tsks["create_repos_conf"]="Create the repos.conf directory.
                              repos.conf directory created."

        tsks["create_resolv_conf"]="Create the resolv.conf file.
                               resolv.conf file created."

        tsks["prepare_chroot"]="Prepare the chroot environment.
                           Chroot environment prepared."

        tsk_ord=("handle_disk" "select_profile" "find_tarball_url" "detect_root_part"
                "mount_root_part" "retrieve_tarball" "extract_tarball"
                "remove_tarball" "create_repos_conf" "create_resolv_conf"
                "prepare_chroot")

        ALLTSK="${#tsks[@]}"
        TSKNO="1"

        trap 'handle_err; cleanup_logs' ERR RETURN
        trap 'cleanup_logs' EXIT INT QUIT TERM

        for funct in "${tsk_ord[@]}"; do
                descript="${tsks[${funct}]}"
                descript="${descript%%$'\n'*}"

                msgdone="$(echo "${tsks[${funct}]}" | tail -n "1" | sed 's/^[[:space:]]*//g')"

                loginf b "${descript}"

                "${funct}"
                loginf g "${msgdone}"

                [[ "${TSKNO}" -eq "${ALLTSK}" ]] && {
                        loginf g "All tsks completed."
                        break
                }

                ((TSKNO++))
        done

        echo "Executing chroot..."
        chroot "/mnt/gentoo" "/bin/bash" && kill -9 "0" > "/dev/null" 2>&1
}

main
