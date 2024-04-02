#!/bin/bash

set -Eeuo pipefail

GREEN='\e[1;92m' RED='\e[1;91m' BLUE='\e[1;94m'
PURPLE='\e[1;95m' YELLOW='\e[1;93m' NC='\033[0m'
CYAN='\e[1;96m' WHITE='\e[1;97m'

handle_error() {
        error_status="${?}"
        command_line="${BASH_COMMAND}"
        error_line="${BASH_LINENO[0]}"

	log_info r "Error on line ${BLUE}${error_line}${RED}: command ${BLUE}'${command_line}'${RED} exited with status: ${BLUE}${error_status}" | tee -a "error_log.txt"
}

trap 'handle_error' ERR
trap 'handle_error' RETURN

cleanup_logs() {
        [[ -f "logfile.txt" ]] && sed -i 's/\x1b\[[0-9;]*m//g; s/\r//g' "logfile.txt"
        sed -i 's/\x1b\[[0-9;]*m//g' "error_log.txt"
}

trap 'cleanup_logs' EXIT

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

confirm_action() {
        while true; do
                echo -en "${GREEN}Do you confirm? (y/n): ${NC}"
                read -r user_input

		[[ "${user_input}" =~ ^[yY](es)?$|^[nN]o?$ ]] && break

		echo -e "${RED}Invalid selection. Choose one of y, Yes, n, No.${NC}"
        done

	[[ "${user_input}" =~ ^[yY](es)?$ ]] && return "0" || return "1"
}

handle_disk() {
        echo -e "${WHITE}Disk operations are extremely critical."
        echo -e "The script can handle proper disk preparation automatically."
        echo -e "You can select your disk and the script will do everything needed."
        echo -e "This process is only valid if you confirm."
        echo -e "If you want to continue by automatic disk preparation then type: ${RED}DELETE_EVERYTHING${WHITE}"
        echo -e "If you have done it yourself or prefer manually doing it then type: ${RED}SKIP${WHITE}"
        echo -e "The script will later check if you have proper BOOT and ROOT partitions."
        echo -e "Type ${RED}DELETE_EVERYTHING${WHITE} or ${RED}SKIP ${CYAN}"
        echo -en "Type here: "

	read -r INPUT

	echo -e "${NC}"

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
                                echo -e "${PURPLE}$((i + 1))) ${YELLOW}${BLOCK_DEVICES[i]}${NC}"
                        done

			echo -ne "${WHITE}Enter the device of your choice: ${CYAN}"

			read -r SELECTED_DEVICE && CHOSEN_DEVICE="${BLOCK_DEVICES[SELECTED_DEVICE - 1]}"

			CHOSEN_DEVICE="${CHOSEN_DEVICE%% *}"
                        echo -e "${GREEN}The chosen device is ${CHOSEN_DEVICE}"

			confirm_action && break

			echo -e "${RED}Declined. Restarting the process...${NC}"
                done

		echo -e "${NC}"

		{ parted -s "${CHOSEN_DEVICE}" print | sed -n 's/^ *\([0-9]\) .*/\1/p' | while read -r part; do
                        parted -s "${CHOSEN_DEVICE}" rm "${part}"
                done; } || true

		parted -s "${CHOSEN_DEVICE}" mklabel gpt
		parted -s "${CHOSEN_DEVICE}" mkpart "efi" fat32 1MiB 250MiB
		parted -s "${CHOSEN_DEVICE}" set 1 esp on

		BOOT_PARTITION="$(lsblk "${CHOSEN_DEVICE}" -lnfo NAME | sed -n 's/^/\/dev\//; 2p')"

		mkfs.vfat -F 32 "${BOOT_PARTITION}"

		echo -e "${WHITE}Enter the size for the ROOT partition."
                echo -e "Leave it empty to use all of the rest."

		while true; do
                        echo -en "${GREEN}Size (e.g 100G): ${CYAN}"
                        read -r selected_size
                        [[ -z "${selected_size}" ]] && {
                                CHOSEN_SIZE="100%"
                                echo -e "${GREEN}You have selected to use all of the remaining space."
                                confirm_action && echo "" ; break
                        }
                        [[ "${selected_size}" =~ ^[1-9][0-9]*[GM]?i?B?$ ]] && {
                                size="${selected_size%%[GMiB]*}"
                                [[ "${selected_size}" =~ [Gg] ]] && size="$((size * 1000))"

				[[ "${size}" -ge "24000" ]] && {
                                        CHOSEN_SIZE="${selected_size}"
                                        echo -e "${GREEN}You have selected a partition size of ${CHOSEN_SIZE}."
                                        confirm_action && echo "" ; break || {
                                                echo -e "${RED}Declined. Restarting the process...${NC}" && continue
                                        }
                                }
                        }

			echo -e "${RED}Invalid format. Please use formats like 20G, 500M, 1GiB, etc."
                        echo -e "It should at least be 24G or 24GiB or 24000M or 24000MiB"
                done

		parted -s "${CHOSEN_DEVICE}" mkpart "linux" 250MiB "${CHOSEN_SIZE}"
                parted -s "${CHOSEN_DEVICE}" type "2" "0fc63daf-8483-4772-8e79-3d69d8477de4"

		echo -e "${WHITE}Select a file system format for ROOT:${NC}"
                echo -e "${WHITE}F2FS is recommended for SSDs and EXT4 for others.${NC}"

		while true; do
                        FS_TYPES=("f2fs" "ext4")

			for i in "${!FS_TYPES[@]}"; do
                                echo -e "${PURPLE}$((i + 1))) ${YELLOW}${FS_TYPES[i]}${NC}"
                        done

			echo -ne "${WHITE}Enter the number of your choice: ${CYAN}"

			read -r SELECTED_FS_TYPE && CHOSEN_FS="${FS_TYPES[SELECTED_FS_TYPE - 1]}"

			[[ -z "${CHOSEN_FS}" ]] || {
                                echo -e "${GREEN}You have selected ${CHOSEN_FS} file system for ROOT."
                        } || {
                                echo -e "${RED}Invalid selection. Please select a valid number."
                                continue
                        }

			confirm_action && break || echo -e "${RED}Declined. Restarting the process...${NC}"
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
        } || echo -e "${BLUE}Skipping disk handling...${NC}"
}

select_profile() {
        AVAILABLE_PROFILES=("stage3-amd64-musl-llvm"
                "stage3-amd64-nomultilib-openrc"
                "stage3-amd64-openrc")

	while true; do
                echo -e "${WHITE}Select a Gentoo profile:${NC}"

		for i in "${!AVAILABLE_PROFILES[@]}"; do
                        echo -e "${PURPLE}$((i + 1))) ${YELLOW}${AVAILABLE_PROFILES[i]}${NC}"
                done

		echo -ne "${WHITE}Enter the number of your choice: ${CYAN}"
                read -r profile_choice && PROFILE="${AVAILABLE_PROFILES[profile_choice - 1]}"

		[[ -z "${PROFILE}" ]] && {
                        echo -e "${RED}Invalid selection. Resetting...${NC}"
                        continue
                }

		echo ""

		echo -e "${GREEN}Selected profile: ${PROFILE}${NC}"
                confirm_action && break || echo -e "${RED}Declined. Resetting...${NC}"
                continue
        done
}

find_tarball_url() {
        URL_GENTOO_WEBSITE="https://www.gentoo.org/downloads/"
        URL_GENTOO_TARBALL="$(curl "${URL_GENTOO_WEBSITE}" | sed -n 's/.*href="\([^"]*'"${PROFILE}"'-[^"]*\.tar\.xz\)".*/\1/p')"
        echo ""
        echo -e "${WHITE}The URL:${CYAN} ${URL_GENTOO_TARBALL}${NC}"
        echo ""
}

detect_root_partition() {
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

        [[ -z "${!partitions[*]}" ]] && {
                log_info r "You do not have any eligible partition for ROOT."
                log_info r "Boot partition should be formatted with vfat FAT32."
                log_info r "Root partition should be formatted with ext4 or f2fs."
                exit "1"
        }

	for i in "${!partitions[@]}"; do
                echo -e "${PURPLE}$((i + 1))) ${YELLOW}${partitions[i]}${NC}"
        done

	echo -ne "${WHITE}Select your preferred ROOT partition: ${CYAN}"
        read -r partition_choice

	partition_info="${partitions[partition_choice - 1]}"
        PARTITION_ROOT="${partition_info%% *}"

	echo -e "The selected ROOT partition is ${PARTITION_ROOT} ${NC}"
        read -rp "Do you want to proceed?: " CONFIRMATION

	[[ "${CONFIRMATION}" =~ [yY](es)? ]] || {
                log_info r "The user has not confirmed the selection."
                exit "1"
        }
}

mount_root_partition() {
        mkdir --parents "/mnt/gentoo"
        mount "${PARTITION_ROOT}" "/mnt/gentoo"
}

retrieve_the_tarball() {
        wget -P "/mnt/gentoo" "${URL_GENTOO_TARBALL}"
}

extract_the_tarball() {
        tar xpf /mnt/gentoo/stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C "/mnt/gentoo"
}

remove_the_tarball() {
        rm -rf /mnt/gentoo/stage3-*.tar.xz
}

create_repos_conf() {
        mkdir --parents "/mnt/gentoo/etc/portage/repos.conf"
        cp -f "/mnt/gentoo/usr/share/portage/config/repos.conf" "/mnt/gentoo/etc/portage/repos.conf/gentoo.conf"
}

create_resolv_conf() {
        cp -f --dereference "/etc/resolv.conf" "/mnt/gentoo/etc/"
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
        declare -A tasks
        tasks["handle_disk"]="Prepare the disk.
		        The disk prepared."

        tasks["select_profile"]="Select a profile.
		           The profile selected."

        tasks["find_tarball_url"]="Find the Gentoo Tarball URL.
		             The Gentoo Tarball URL found."

        tasks["detect_root_partition"]="Detect and Choose Partition.
			          Partition Chosen."

        tasks["mount_root_partition"]="Mount the root partition.
                                 Root partition mounted."

        tasks["retrieve_the_tarball"]="Retrieve the Gentoo Tarball.
                                 Gentoo Tarball retrieved."

        tasks["extract_the_tarball"]="Extract the Gentoo Tarball.
                                Gentoo Tarball extracted."

        tasks["remove_the_tarball"]="Remove the Gentoo Tarball.
                               Gentoo Tarball removed."

        tasks["create_repos_conf"]="Create the repos.conf directory.
                              repos.conf directory created."

        tasks["create_resolv_conf"]="Create the resolv.conf file.
                               resolv.conf file created."

        tasks["prepare_chroot"]="Prepare the chroot environment.
                           Chroot environment prepared."

        task_order=("handle_disk" "select_profile" "find_tarball_url" "detect_root_partition"
                "mount_root_partition" "retrieve_the_tarball" "extract_the_tarball"
                "remove_the_tarball" "create_repos_conf" "create_resolv_conf"
                "prepare_chroot")

        TOTAL_TASKS="${#tasks[@]}"
        TASK_NUMBER="1"

        for function in "${task_order[@]}"; do
                description="${tasks[${function}]}"
                description="${description%%$'\n'*}"

		done_message="$(echo "${tasks[${function}]}" | tail -n "1" | sed 's/^[[:space:]]*//g')"

		log_info b "${description}"

		"${function}"
		log_info g "${done_message}"

		[[ "${TASK_NUMBER}" -eq "${TOTAL_TASKS}" ]] && {
			log_info g "All tasks completed."
			break
		}

		((TASK_NUMBER++))
        done
}

main
echo "Executing chroot..."
chroot "/mnt/gentoo" "/bin/bash" && kill "0"
