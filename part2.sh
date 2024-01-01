#!/bin/bash

# This script installs and configures a fully functioning, completely
# configured Gentoo Linux system. The script should be run after chrooting.

# Define URLs for the files here:
# Useflags for specific packages.
URL_DOTFILES="https://github.com/emrakyz/dotfiles.git"
# PACKAGES WE INSTALL ##
URL_DEPENDENCIES_TXT="https://raw.githubusercontent.com/emrakyz/dotfiles/main/dependencies.txt"
# PORTAGE FILES #
URL_PACKAGE_USE="https://raw.githubusercontent.com/emrakyz/dotfiles/main/portage/package.use"
URL_ACCEPT_KEYWORDS="https://raw.githubusercontent.com/emrakyz/dotfiles/main/portage/package.accept_keywords"
URL_PACKAGE_ENV="https://raw.githubusercontent.com/emrakyz/dotfiles/main/portage/package.env"
URL_USE_MASK="https://raw.githubusercontent.com/emrakyz/dotfiles/main/portage/profile/use.mask"
URL_PACKAGE_UNMASK="https://raw.githubusercontent.com/emrakyz/dotfiles/main/portage/profile/package.unmask"
# SPECIFIC COMPILER ENVIRONMENTS #
URL_CLANG_O3_LTO="https://raw.githubusercontent.com/emrakyz/dotfiles/main/portage/env/clang_o3_lto"
URL_CLANG_O3_LTO_FPIC="https://raw.githubusercontent.com/emrakyz/dotfiles/main/portage/env/clang_o3_lto_fpic"
URL_GCC_O3_LTO="https://raw.githubusercontent.com/emrakyz/dotfiles/main/portage/env/gcc_o3_lto"
URL_GCC_O3_LTO_FFATLTO="https://raw.githubusercontent.com/emrakyz/dotfiles/main/portage/env/gcc_o3_lto_ffatlto"
URL_GCC_O3_NOLTO="https://raw.githubusercontent.com/emrakyz/dotfiles/main/portage/env/gcc_o3_nolto"
# LINUX KERNEL CONFIGURATION #
URL_KERNEL_CONFIG="https://raw.githubusercontent.com/emrakyz/dotfiles/main/kernel_6_6_4_config"
URL_TEXLIVE_PROFILE="https://raw.githubusercontent.com/emrakyz/dotfiles/main/texlive.profile"
URL_TEXLIVE_INSTALL="https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz"
# ZSH PLUGINS #
URL_FZF_TAB="https://github.com/Aloxaf/fzf-tab.git"
URL_ZSH_AUTOSUGGESTIONS="https://github.com/zsh-users/zsh-autosuggestions.git"
URL_SYNTAX_HIGHLIGHT="https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
URL_POWERLEVEL10K="https://github.com/romkatv/powerlevel10k.git"
URL_WAL_VIM="https://raw.githubusercontent.com/emrakyz/dotfiles/main/wal.vim"
# BLACKLISTED ADRESSES TO BLOCK #
# THE BELOW LINK BLACKLISTS ADWARE, #
# MALWARE, FAKENEWS, GAMBLING, PORN, SOCIAL MEDIA #
URL_HOSTS_BLACKLIST="https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts"
# Settings for Busybox to only enable udhcpc and its scripts.
URL_BUSYBOX_CONFIG="https://raw.githubusercontent.com/emrakyz/dotfiles/main/busybox-9999"
URL_DEFAULT_SCRIPT="https://raw.githubusercontent.com/emrakyz/dotfiles/main/default.script"
URL_UDHCPC_INIT="https://raw.githubusercontent.com/emrakyz/dotfiles/main/udhcpc"
# Local Gentoo Repos.
URL_LOCAL="https://github.com/emrakyz/local.git"

# DEFINE DIRS HERE #
# FILES_DIR is a temporary directory to put the above downloaded files.
FILES_DIR="/root/files"
PORTAGE_DIR="/etc/portage"
PORTAGE_PROFILE_DIR="/etc/portage/profile"
PORTAGE_ENV_DIR="/etc/portage/env"
LINUX_DIR="/usr/src/linux"
NEW_KERNEL="$LINUX_DIR/arch/x86/boot/bzImage"
KERNEL_PATH="/boot/EFI/BOOT/BOOTX64.EFI"
BUSYBOX_CONFIG_DIR="/etc/portage/savedconfig/sys-apps"
UDHCPC_INIT_DIR="/etc/init.d"
UDHCPC_SCRIPT_DIR="/etc/udhcpc"
LOCAL_REPO_DIR="/var/db/repos/local"

# Fail Fast & Fail Safe on errors and stop.
set -Eeo pipefail

# Use HIGHLIGHTED-BOLD color variants for our logs.
GREEN='\e[1;92m' RED='\e[1;91m' BLUE='\e[1;94m'
PURPLE='\e[1;95m' YELLOW='\e[1;93m' NC='\033[0m'
CYAN='\e[1;96m' WHITE='\e[1;97m'

log_info() {
    sleep 0.3

    # Choose color based on input.
    case $1 in
        g) COLOR=$GREEN MESSAGE='DONE!' ;;
        r) COLOR=$RED MESSAGE='WARNING!' ;;
        b) COLOR=$BLUE MESSAGE="STARTING..." ;;
        c) COLOR=$BLUE MESSAGE="RUNNING..." ;;
    esac

    # If the message doesn't start with a task counter format, use the global TASK_NUMBER and TOTAL_TASKS
    COLORED_TASK_INFO="${WHITE}(${CYAN}${TASK_NUMBER}${PURPLE}/${CYAN}${TOTAL_TASKS}${WHITE})"
    MESSAGE_WITHOUT_TASK_NUMBER="$2"

    FULL_LOG="${CYAN}[${PURPLE}$(date '+%Y-%m-%d '${CYAN}'/'${PURPLE}' %H:%M:%S')${CYAN}] ${YELLOW}>>>${COLOR}$MESSAGE${YELLOW}<<< $COLORED_TASK_INFO - ${COLOR}$MESSAGE_WITHOUT_TASK_NUMBER${NC}"

    # Display the message. If the message is for the current task then append a new line to increase readibility.
    { [[ $1 = c ]] && echo -e "\n\n$FULL_LOG"; } || echo -e "$FULL_LOG"
}

# Error handler function. This will show which command failed.
handle_error () {
    error_status=$?
    command_line=${BASH_COMMAND}
    error_line=${BASH_LINENO[0]}
    log_info r "Error on line ${BLUE}$error_line${RED}: command ${BLUE}'${command_line}'${RED} exited with status: ${BLUE}$error_status" |
    tee -a error_log.txt
}

trap 'handle_error' ERR
trap 'handle_error' RETURN

cleanup_logs() {
    [ -f "logfile.txt" ] && sed -i 's/\x1b\[[0-9;]*m//g; s/\r//g' logfile.txt
    sed -i 's/\x1b\[[0-9;]*m//g' error_log.txt
}

trap cleanup_logs EXIT

# Prepare the environment.
prepare_env() {
    source /etc/profile
 #   export PS1="(chroot) ${PS1}"
}

show_options_grid() {
    local options=("$@")
    for i in "${!options[@]}"; do
        printf "${YELLOW}%2d) ${PURPLE}%-15s${NC}" "$((i + 1))" "${options[i]}"
        (( (i + 1) % 3 == 0 )) && echo
    done
    (( ${#options[@]} % 3 != 0 )) && echo
}

select_timezone() {
    while true; do
        regions=($(find /usr/share/zoneinfo/* -maxdepth 0 -type d -exec basename {} \; | grep -vE 'Arctic|Antarctica|Etc'))
        show_options_grid "${regions[@]}"
        echo -ne "${CYAN}Select a region: ${NC}"
        read region_choice
        selected_region=${regions[region_choice - 1]}
        echo -e "${GREEN}Region selected: $selected_region${NC}"

        echo -ne "${CYAN}Confirm region? (y/n): ${NC}"
        read confirm_region
        [[ $confirm_region =~ ^[yY](es)?$ ]] || { echo -e "${RED}Selection canceled, restarting...${NC}"; continue; }

        cities=($(find /usr/share/zoneinfo/$selected_region/* -maxdepth 0 -exec basename {} \;))
        show_options_grid "${cities[@]}"
        echo -ne "${CYAN}Select a city: ${NC}"
        read city_choice
        selected_city=${cities[city_choice - 1]}
        echo -e "${GREEN}Timezone selected: $selected_region/$selected_city${NC}"

        echo -ne "${CYAN}Confirm timezone? (y/n): ${NC}"
        read confirm_city
        [[ $confirm_city =~ ^[yY](es)?$ ]] && break
        echo -e "${RED}Selection canceled, restarting...${NC}"
    done

    TIME_ZONE="$selected_region/$selected_city"
}

select_gpu() {
    valid_gpus=(via v3d vc4 virgl vesa ast mga qxl i965 r600 i915 r200 r100 r300 lima omap r128 radeon geode vivante nvidia fbdev dummy intel vmware glint tegra d3d12 exynos amdgpu nouveau radeonsi virtualbox panfrost lavapipe freedreno siliconmotion)

    while true; do
        show_options_grid "${valid_gpus[@]}"
        echo -ne "${CYAN}Select a GPU: ${NC}"
        read gpu_choice
        selected_gpu=${valid_gpus[gpu_choice - 1]}
        echo -e "${GREEN}GPU selected: $selected_gpu${NC}"

        echo -ne "${CYAN}Confirm GPU? (y/n): ${NC}"
        read confirm_gpu
        [[ $confirm_gpu =~ ^[yY](es)?$ ]] && break
        echo -e "${RED}Selection canceled, restarting...${NC}"
    done
}

# Collect the first needed variables.
collect_variables() {
    # Find partitions mounted to / and /boot. then get their IDs.
    # These are needed for configuring the kernel and fstab.
    PARTITION_ROOT="$(findmnt -n -o SOURCE /)"

    # The below command finds the boot partition. 0 in lsblk (RM) means non removable.
    # The sed command specifically searches for 0 and the below EFI System code then add /dev
    # to the result to get an output similar to this: "/dev/nvme0n1p1". If there is no matchin partition
    # , user will get an appropriate error with the next function.
    PARTITION_BOOT="$(lsblk -nlo NAME,RM,PARTTYPE |
	    sed -n '/0\s*c12a7328-f81f-11d2-ba4b-00a0c93ec93b/ {s|^[^ ]*|/dev/&|; s| .*||p; q}')"

    UUID_ROOT="$(blkid -s UUID -o value "$PARTITION_ROOT")"
    UUID_BOOT="$(blkid -s UUID -o value "$PARTITION_BOOT")"
    PARTUUID_ROOT="$(blkid -s PARTUUID -o value "$PARTITION_ROOT")"
}

select_external_hdd() {
    echo -e "${WHITE}Do you have another partition you want to mount with boot? (y/n):${YELLOW}"
    read EXTERNAL_HDD
    echo -e "${NC}"

    [[ $EXTERNAL_HDD =~ ^[yY](es)?$ ]] && {

    while true; do
        echo -e "${WHITE}Available Partitions:${NC}"
        IFS=$'\n' partitions=($(lsblk -lnfo NAME,FSTYPE,SIZE | sed -E 's/^/\/dev\//; /vfat/d; \|'"${PARTITION_ROOT}"'|d; /^[^ ]*[a-z] /d; /^[^ ]*n[0-9][^p] /d; /^[^ ]+\s+[^ ]+\s*$/d'))
        unset IFS

        for i in "${!partitions[@]}"; do
            echo -e "${PURPLE}$((i + 1))) ${YELLOW}${partitions[i]}${NC}"
        done

        echo -ne "${WHITE}Select a partition number: ${CYAN}"
        read partition_choice
	partition_info="${partitions[partition_choice - 1]}"
	PARTITION_EXTERNAL=${partition_info%% *}

	filesystem_type=($partition_info)
	filesystem_type="${filesystem_type[1]}"

        echo -ne "${WHITE}Enter the mount path (e.g., /mnt/harddisk): ${CYAN}"
        read mount_path

        echo -e "${GREEN}Selected Partition: $PARTITION_EXTERNAL${NC}"
        echo -e "${GREEN}Filesystem Type: $filesystem_type${NC}"
        echo -e "${GREEN}Mount Path: $mount_path${NC}"

	echo -ne "${CYAN}Confirm external hdd? (y/n): ${NC}"
        read confirm_external_hdd
        [[ $confirm_external_hdd =~ ^[yY](es)?$ ]] && break
        echo -e "${RED}Selection canceled, restarting...${NC}"
    done; } || log_info b "No extra partitions specified. Skipping..."
    [[ "$EXTERNAL_HDD" =~ [Yy](es)? ]] && EXTERNAL_UUID="$(blkid -s UUID -o value "$PARTITION_EXTERNAL")" || true
}

# Check if above variables properly collected.
check_first_vars() {
    # Check if the boot partition exists.
    lsblk "$PARTITION_BOOT" > /dev/null 2>&1 || {
	    log_info r "Partition $PARTITION_BOOT does not exist."; exit 1; }

    # Check if the disk is GPT labeled. If not, inform the user and stop.
    DISK="${PARTITION_BOOT%[0-9]*}"
    DISK="${DISK%p}"
    fdisk -l "$DISK" | grep -q "Disklabel type: gpt" || {
	    log_info r "Your disk device is not 'GPT labeled'. Exit chroot first."
    	    log_info r "Use fdisk on your device without its partition: '/dev/nvme0n1'"
	    log_info r "Delete every partition by typing 'd' and 'enter' first."
	    log_info r "Type g (lower-cased) and enter to create a GPT label."
	    log_info r "Then create 2 partitions for boot and root by typing 'n'."
    	    exit 1; }

    # Check if the boot partition has 'EFI System' type.
    BOOT_PART_TYPE=$(lsblk -nlo PARTTYPE $PARTITION_BOOT)
    [ "$BOOT_PART_TYPE" = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ] || {
	    log_info r "The boot partition does not have 'EFI System' type."
	    log_info r "Use fdisk on your device '/dev/nvme0n1' without its partition."
	    log_info r "Type 't' and enter. Select the related partition. Then make it 'EFI System'."
    	    exit 1; }

    # Check if the boot partition is formatted as 'vfat FAT32'.
    BOOT_FS_TYPE=$(blkid -o value -s TYPE $PARTITION_BOOT)
    [ "$BOOT_FS_TYPE" = "vfat" ] || {
	    log_info r "The boot partition should be formatted as 'vfat FAT32'."
	    log_info r "Use 'mkfs.vfat -F 32 /dev/<your-partition>'."
	    log_info r "You need 'sys-fs/dosfstools' for this operation."
    	    exit 1; }

    # Check if the root partition has 'Linux Filesystem' type
    ROOT_PART_TYPE=$(lsblk -nlo PARTTYPE $PARTITION_ROOT)
    [ "$ROOT_PART_TYPE" = "0fc63daf-8483-4772-8e79-3d69d8477de4" ] || {
	    log_info r "The root partition does not have 'Linux Filesystem' type."
    	    log_info r "Use fdisk on your device '/dev/nvme0n1' without its partition."
	    log_info r "Type 't' and enter. Select the related partition. Then make it 'Linux Filesystem'."
    	    exit 1; }

    # Check if the root partition is formatted with 'ext4'
    ROOT_FS_TYPE=$(blkid -o value -s TYPE $PARTITION_ROOT)
    [ "$ROOT_FS_TYPE" = "ext4" ] || {
	    log_info r "The root partition is not formatted with 'ext4'."
    	    log_info r "Use 'mkfs.ext4 /dev/<your-partition>'."
	    exit 1; }

    # Check if the timezone given appropriate.
    TZ_FILE="/usr/share/zoneinfo/${TIME_ZONE}"
    [ -f "$TZ_FILE" ] || {
	    log_info r "The timezone $TIME_ZONE is invalid or does not exist."; exit 1; }

    # Check if all IDs collected properly.
    { [ -n "$UUID_ROOT" ] && [ -n "$UUID_BOOT" ] && [ -n "$PARTUUID_ROOT" ]
    } || { log_info r "Critical partition information is missing."; exit 1; }

    # Check if GPU given is appropriate.
    # Check if the entered GPU is in the list of valid GPUs and does not contain spaces.
    { [[ " ${valid_gpus[@]} " =~ " $selected_gpu " ]] && [[ ! "$selected_gpu" =~ [[:space:]] ]]
    } || { log_info r "Invalid GPU. Please enter a valid GPU."; exit 1; }
}

# Account information is needed in order to create a user.
collect_credentials() {
    echo -e "${WHITE}Enter the Username:${YELLOW}"
    read USERNAME
    echo -e "${WHITE}Enter the Password:${YELLOW}"
    read -s PASSWORD
    echo -e "${WHITE}Confirm the Password:${YELLOW}"
    read -s PASSWORD2

    echo ""
    echo -e "${NC}"
}

# Check if the given credentials are proper.
check_credentials() {
    # Check if the username contains only alphanumeric characters, underscores, and dashes.
    [[ "$USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]] || {
    log_info r "Invalid username. Only alphanumeric characters, underscores, and dashes are allowed."; exit 1; }

    # Check if passwords match and are not empty.
    { [ "$PASSWORD" = "$PASSWORD2" ] && [ -n "$PASSWORD" ]
    } || { log_info r "Passwords do not match or are empty."; exit 1; }
}

# Sync the Gentoo Repositories with the newest ones.
# We also need Git in order to pull our repositories.
sync_repos() {
    # emerge --sync --quiet
    echo ""
    # emerge dev-vcs/git
}

# File Associations with URL, Download Location, and Final Destination.
declare -A associate_files

associate_f() {
    local key=$1
    local url=$2
    local base_path=$3

    # Constructing the final path by appending the key to the base path.
    local final_path="$base_path/$key"

    associate_files["$key"]="$url $FILES_DIR/$key $final_path"
}

# Set file associations. Updating could be singular but there is no need
# since it's instant and not problematic. Some of them does not have final location.
update_associations() {
    associate_f "package.use" "$URL_PACKAGE_USE" "$PORTAGE_DIR"
    associate_f "package.accept_keywords" "$URL_ACCEPT_KEYWORDS" "$PORTAGE_DIR"
    associate_f "package.env" "$URL_PACKAGE_ENV" "$PORTAGE_DIR"
    associate_f "use.mask" "$URL_USE_MASK" "$PORTAGE_PROFILE_DIR"
    associate_f "package.unmask" "$URL_PACKAGE_UNMASK" "$PORTAGE_PROFILE_DIR"
    associate_f ".config" "$URL_KERNEL_CONFIG" "$LINUX_DIR"
    associate_f "clang_o3_lto" "$URL_CLANG_O3_LTO" "$PORTAGE_ENV_DIR"
    associate_f "clang_o3_lto_fpic" "$URL_CLANG_O3_LTO_FPIC" "$PORTAGE_ENV_DIR"
    associate_f "gcc_o3_lto" "$URL_GCC_O3_LTO" "$PORTAGE_ENV_DIR"
    associate_f "gcc_o3_nolto" "$URL_GCC_O3_NOLTO" "$PORTAGE_ENV_DIR"
    associate_f "gcc_o3_lto_ffatlto" "$URL_GCC_O3_LTO_FFATLTO" "$PORTAGE_ENV_DIR"
    associate_f "blacklist_hosts.txt" "$URL_HOSTS_BLACKLIST"
    associate_f "fzf-tab" "$URL_FZF_TAB" "$ZDOTDIR"
    associate_f "zsh-autosuggestions" "$URL_ZSH_AUTOSUGGESTIONS" "$ZDOTDIR"
    associate_f "zsh-fast-syntax-highlighting" "$URL_SYNTAX_HIGHLIGHT" "$ZDOTDIR"
    associate_f "powerlevel10k" "$URL_POWERLEVEL10K" "$ZDOTDIR"
    associate_f "texlive.profile" "$URL_TEXLIVE_PROFILE" "$TEX_DIR"
    associate_f "dependencies.txt" "$URL_DEPENDENCIES_TXT"
    associate_f "dotfiles" "$URL_DOTFILES"
    associate_f "busybox-9999" "$URL_BUSYBOX_CONFIG" "$BUSYBOX_CONFIG_DIR"
    associate_f "default.script" "$URL_DEFAULT_SCRIPT" "$UDHCPC_SCRIPT_DIR"
    associate_f "udhcpc" "$URL_UDHCPC_INIT" "$UDHCPC_INIT_DIR"
    associate_f "local" "$URL_LOCAL"
    associate_f "install-tl-unx.tar.gz" "$URL_TEXLIVE_INSTALL"
    associate_f "wal.vim" "$URL_WAL_VIM" "$WAL_VIM_DIR"
}

update_associations

# Move the files according to associative array.
move_file() {
    local key=$1
    local custom_destination=${2:-}  # Optional custom destination.
    local download_path final_destination
    read -r _ download_path final_destination <<< "${associate_files[$key]}"

    # Move the file.
    mv "$download_path" "$final_destination"
}

# Display the progress bar. This is a fun way to see the progress for the files
# we download from links at the start of the script.
update_progress() {
    local total=$1
    local current=$2
    local pct=$(( (current * 100) / total ))
    local filled_blocks=$((pct * 65 / 100))
    local empty_blocks=$((65 - filled_blocks))
    local bar=''

    # Filled part of the bar.
    for i in $(seq 1 $filled_blocks); do
        bar="${bar}${GREEN}#${NC}"
    done

    # Empty part of the bar.
    for i in $(seq 1 $empty_blocks); do
        bar="${bar}${RED}-${NC}"
    done

    # Print the progress bar with the percentage in purple.
    echo -ne "\r\033[K$bar${PURPLE} $pct%${NC}"
}

# Determine and handle download type.
download_file() {
    local source=$1
    local dest=$2

    # Check for directory existence and skip Git cloning if it exists.
    [ -d "$dest" ] && {
        log_info b "Directory $dest already exists, skipping download."
        return
    }

    # Check for file existence and skip downloading if it exists.
    [ -f "$dest" ] && {
        log_info b "File $dest already exists, skipping download."
        return
    }

    # Handling Powerlevel10k Git repository clone.
    [[ "$source" == *powerlevel10k* ]] && { git clone --depth=1 "$source" "$dest" > /dev/null 2>&1; return; }

    # Handling other Git repository clones.
    [[ "$source" == *".git" ]] && [[ "$source" != *powerlevel10k.git* ]] && { git clone "$source" "$dest" > /dev/null 2>&1; return; }

    # Handling regular file URLs.
    curl -L "$source" -o "$dest" > /dev/null 2>&1
}

# Function to Retrieve All Files with Progress Bar.
retrieve_files() {
    mkdir -p "$FILES_DIR"
    local total="${#associate_files[@]}"
    local current=0

    echo -ne "\033[?25l"

    for key in "${!associate_files[@]}"; do
        current="$((current + 1))"
        update_progress "$total" "$current"

        read -r source dest _ <<< "${associate_files[$key]}"
        download_file "$source" "$dest"
    done

    echo ""

    echo -e "\033[?25h"
}

# Check the files we downloaded.
check_files() {
    for key in "${!associate_files[@]}"; do
        read -r _ f _ <<< "${associate_files["$key"]}"
        [ -s "$f" ] || [ -d "$f" ] || { log_info r "$f is missing."; kill 0; }
    done
}

# This command used several times in order to renew the environment after some changes.
renew_env() {
    env-update && source /etc/profile && export PS1="(chroot) ${PS1}"
}

# Configure the localization settings.
configure_locales() {
    log_info r "EXITING now... The demo is ended." && kill 0
    # Remove the "#" before English UTF setting.
    sed -i "/#en_US.UTF/ s/#//g" /etc/locale.gen

    # Generate locales after enabling English UTF.
    locale-gen

    # Select the generated locale.
    eselect locale set en_US.utf8

    # Add locales for the compiler.
    echo 'LC_COLLATE="C.UTF-8"' >> /etc/env.d/02locale

    # Renew the environment.
    renew_env
}

# Configure compiler flags for the global environment.
configure_flags() {
    # We will use the safest "-O2 -march=native -pipe" flags.
    # Add LDFLAGS AND RUSTFLAGS below FFLAGS.
    sed -i '/COMMON_FLAGS=/ c\COMMON_FLAGS="-march=native -O2 -pipe"
            /^FFLAGS/ a\LDFLAGS="-Wl,-O2 -Wl,--as-needed"
	    /^FFLAGS/ a\RUSTFLAGS="-C debuginfo=0 -C codegen-units=1 -C target-cpu=native -C opt-level=3"' /etc/portage/make.conf

    # Find CPU flags and append them to make.conf file.
    # The command's output is not proper for make.conf so we modify it.
    emerge --oneshot app-portage/cpuid2cpuflags
    cpuid2cpuflags | sed 's/: /="/; s/$/"/' >> /etc/portage/make.conf

    echo "" >> /etc/portage/make.conf

    # Enable rolling release packages and use the latest version targets.
    cat <<-EOF >> /etc/portage/make.conf
	ACCEPT_KEYWORDS="~amd64"
	RUBY_TARGETS="ruby32"
	RUBY_SINGLE_TARGET="ruby32"
	PYTHON_TARGETS="python3_12"
	PYTHON_SINGLE_TARGET="python3_12"
	LUA_TARGETS="lua5-4"
	LUA_SINGLE_TARGET="lua5-4"
	EOF
}

# Configure additional Portage features
configure_portage() {
    # We will accept all licenses by default.
    { echo "ACCEPT_LICENSE=\"*\""

      # Set the video card variable.
      echo "VIDEO_CARDS=\"$GPU\""

      # We will make it extra safe for precaution. So we don't use all cores.
      echo "MAKEOPTS=\"-j$(( $(nproc) - 2)) -l$(( $(nproc) - 2))\""

      # We will use idle mode for Portage in order to use the computer while compiling software.
      echo "PORTAGE_SCHEDULING_POLICY=\"idle\""

      # For the installation, it would be safer to compile single program at once.
      # We also set some sane defaults for the emerge command.
      echo "EMERGE_DEFAULT_OPTS=\"--jobs=1 --load-average=$(( $(nproc) - 2)) --keep-going --verbose --quiet-build --with-bdeps=y --complete-graph=y --deep\""

      # Disable default use flags and add sane defaults.
      echo "USE=\"-* minimal wayland pipewire clang native-symlinks lto pgo jit xs orc threads asm openmp libedit custom-cflags system-man system-libyaml system-lua system-bootstrap system-llvm system-lz4 system-sqlite system-ffmpeg system-icu system-av1 system-harfbuzz system-jpeg system-libevent system-librnp system-libvpx system-png system-python-libs system-webp system-ssl system-zlib system-boost\""

      # Some default self-defining features for Portage.
      echo "FEATURES=\"candy fixlafiles unmerge-orphans nodoc noinfo notitles parallel-install parallel-fetch clean-logs\""

      # This is needed for Mandoc. We will use Mandoc for manpages.
      echo "PORTAGE_COMPRESS_EXCLUDE_SUFFIXES=\"[1-9] n [013]p [1357]ssl\"
PORTAGE_COMPRESS=gzip"
    }  >> /etc/portage/make.conf
}

# Remove non-needed directories. Use text files instead.
remove_dirs() {
    rm -rf /etc/portage/package.use
    rm -rf /etc/portage/package.accept_keywords
}

# Configure package-specific useflags.
configure_useflags() {
    # Remove the directory first so we can use a text file instead.
    remove_dirs

    # Copy the Portage related files we downloaded.
    move_file package.use
    move_file package.accept_keywords
    move_file use.mask
    move_file package.unmask
}

# Move the custom compiler environment files. We move the files first but these will be
# activated after when we will have updated GCC and compiled Clang/Rust Toolchain.
move_compiler_env() {
    mkdir -p $PORTAGE_ENV_DIR
    move_file clang_o3_lto
    move_file clang_o3_lto_fpic
    move_file gcc_o3_lto
    move_file gcc_o3_nolto
    move_file gcc_o3_lto_ffatlto
}

# Now we can completely update the system.
update_system() {
    # Renew the environment just in case.
    renew_env

    # Use mandoc for manpages.
    emerge app-text/mandoc

    # Update all packages with new use flags and settings.
    emerge --update --newuse -e @world

    # Rebuild the packages that need to be because of shared files.
    emerge @preserved-rebuild

    # Remove the unnecessary packages.
    emerge --depclean

    # Renew again after the update.
    renew_env
}

# We will build these first and recompile again with their environment files.
build_clang_rust() {
    # Building Clang with GCC can be problematic so we will make it even slower.
    # We will only activate 2/3 of our threads. eg. 12 out of 16.
    NEW_MAKEOPTS="$(( $(nproc) * 2 / 3 ))"

    MAKEOPTS="-j$NEW_MAKEOPTS -l$NEW_MAKEOPTS" emerge dev-lang/rust sys-devel/clang

    # Since we have Clang/Rust Toolchain; we can activate their environment.
    # Now we will rebuild them with their own toolchain and then rebuild
    # the whole system excluding Clang/Rust toolchain.
    move_file package.env

    renew_env

    # Now we can rebuild whole toolchain related files with Clang/Rust toolchain
    # using optimizations.
    MAKEOPTS="-j$NEW_MAKEOPTS -l$NEW_MAKEOPTS" emerge --oneshot sys-devel/clang dev-libs/jsoncpp dev-libs/libuv sys-devel/llvm sys-devel/llvm-common sys-devel/llvm-toolchain-symlinks sys-devel/lld sys-libs/libunwind sys-libs/compiler-rt sys-libs/compiler-rt-sanitizers sys-devel/clang-common dev-util/cmake sys-devel/clang-runtime sys-devel/clang-toolchain-symlinks sys-libs/libomp dev-lang/rust dev-lang/perl dev-lang/python dev-util/ninja dev-util/samurai dev-python/sphinx dev-libs/libedit

    # Clean-up if needed.
    emerge --depclean

    # Rebuild GCC toolchain with its updated environment.
    emerge sys-devel/gcc
    renew_env
    emerge sys-libs/glibc sys-devel/binutils

    # Rebuild the world but exclude the packages we just compiled.
    emerge -e @world --exclude 'sys-devel/clang dev-libs/jsoncpp dev-libs/libuv sys-devel/llvm sys-devel/llvm-common sys-devel/llvm-toolchain-symlinks sys-devel/lld sys-libs/libunwind sys-libs/compiler-rt sys-libs/compiler-rt-sanitizers sys-devel/clang-common dev-util/cmake sys-devel/clang-runtime sys-devel/clang-toolchain-symlinks sys-libs/libomp dev-lang/rust dev-lang/perl dev-lang/python dev-util/ninja dev-util/samurai dev-python/sphinx dev-libs/libedit sys-devel/gcc sys-libs/glibc sys-devel/binutils'
}

# We can set the timezone now.
set_timezone() {
    # Remove the current time file if exists.
    rm /etc/localtime

    # Use our timezone variable.
    echo "$TIME_ZONE" > /etc/timezone

    # Configure timezone.
    emerge --config sys-libs/timezone-data
}

# We need the Intel Microcode updated specifically for our CPU.
set_cpu_microcode() {
    # First use a generic flac since we don't know the signature yet.
    echo 'MICROCODE_SIGNATURES="-S"' >> /etc/portage/make.conf

    # Emerge the microcode package.
    emerge sys-firmware/intel-microcode

    # Now we have the package so we can learn the microcode now.
    SIGNATURE="$(iucode_tool -S 2>&1 | grep -o "0x0.*$")"

    # Change the temporal setting.
    sed -i "/MICROCODE/ s/-S/-s $SIGNATURE/" /etc/portage/make.conf

    # Recompile again with the new setting.
    emerge sys-firmware/intel-microcode
}

# Configure GPU Related Linux Firmware.
set_linux_firmware() {
    # Emerge without xz support since we don't have the kernel yet.
    USE="-compress-xz" emerge linux-firmware

    { [[ "$GPU" =~ nvidia ]] && {
    	# pciutils is needed to find our GPU Code.
    	emerge --oneshot pciutils

        GPU_CODE="$(lspci | grep -i 'vga\|3d\|2d' |
	               sed -n '/NVIDIA Corporation/{s/.*NVIDIA Corporation \([^ ]*\).*/\L\1/p}' |
		       sed 's/m$//')"
	       	       } || true

        # Remove all Linux Firmware except the ones we need for the GPU.
        sed -i '/^nvidia\/'"$GPU_CODE"'/!d' /etc/portage/savedconfig/sys-kernel/linux-firmware-*
    } || log_info b "Not using Nvidia... Skipping the debloating process for Linux Firmware."
}

# Solve the dependency conflict for text rendering and rasterization.
build_freetype() {
    # Freetype package should be compiled without Harfbuzz support first.
    USE="-harfbuzz" emerge --oneshot freetype

    # Then we can compile it again with Harfbuzz support.
    # Use oneshot since we don't want to add these into world file.
    emerge --oneshot freetype
}

# Now we can build the Gentoo Linux Kernel.
build_linux() {
    # Download the source for the lates Linux Kernel.
    emerge gentoo-sources

    # Move our .config file we downloaded before.
    move_file ".config"

    # Use the variable we got at first. Then also actiave openrc-init. If the user has nvidia, enable it.
    sed -i "/^CONFIG_CMDLINE=.*/ c\CONFIG_CMDLINE=\"root=PARTUUID=$PARTUUID_ROOT init=/sbin/openrc-init\"" "$LINUX_DIR"/.config

    # Arch Wiki: Nvidia Page
    [[ "$GPU" =~ nvidia ]] && sed -i "/^CONFIG_CMDLINE=.*/ s/\"$/ nvidia_drm.modeset=1 fbdev=1\"/" "$LINUX_DIR"/.config

    # Find our CPU Microcode Path.
    MICROCODE_PATH="$(iucode_tool -S -l /lib/firmware/intel-ucode/* 2>&1 |
	             grep 'microcode bundle' |
		     awk -F': ' '{print $2}' |
		     cut -d'/' -f4-)"

    # We will add the number of threads in the kernel config.
    THREAD_NUM=$(nproc)

    # 1- Use the found CPU Microcode Path.
    # 2- Add the number of threads to the kernel config.
    # Use `|` as a delimeter because forward slashes inside microcode path
    # can be interpreted as a part of the command.
    sed -i "/CONFIG_EXTRA_FIRMWARE=/ s|=.*|=\"$MICROCODE_PATH\"|
            /CONFIG_NR_CPUS=/ s|=.*|=$THREAD_NUM|" "$LINUX_DIR"/.config

    # Set the configuration file. We are using LTO + O3 optimizations with Clang compiler.
    LLVM=1 LLVM_IAS=1 CFLAGS="-O3 -march=native -pipe" make -C "$LINUX_DIR" olddefconfig

    # Build the kernel.
    LLVM=1 LLVM_IAS=1 CFLAGS="-O3 -march=native -pipe" make -C "$LINUX_DIR" -j"$(nproc)"

    # Everytime a new kernel built, nvidia drivers need to be emerged.
    # Add PAT support to the nvidia.conf. Refer to Arch Wiki Page: "Nvidia".
    { [[ "$GPU" =~ nvidia ]] && emerge x11-drivers/nvidia-drivers
        echo "options nvidia NVreg_UsePageAttributeTable=1" >> /etc/modprobe.d/nvidia.conf
    } || log_info b "Not using Nvidia... Skipping..."

    # Since we have the kernel, we can build linux-firmware with xz.
    emerge sys-kernel/linux-firmware

    # Install the modules.
    LLVM=1 LLVM_IAS=1 CFLAGS="-O3 -march=native -pipe" make -C "$LINUX_DIR" modules_install

    # Mount the boot partition in order to copy the kernel.
    mount "$PARTITION_BOOT" /boot

    # Create the necessary directory for UEFI.
    mkdir -p "/boot/EFI/BOOT"

    # Copy the kernel to its location.
    cp "$NEW_KERNEL" "$KERNEL_PATH"
}

# Create fstab file with our partition variables.
generate_fstab() {
    # This is the Boot partition.
    echo "UUID=$UUID_BOOT /boot vfat defaults,noatime 0 2" > /etc/fstab

    # This is the Root partition.
    echo "UUID=$UUID_ROOT / ext4 defaults,noatime 0 1" >> /etc/fstab

    # If the user has an external HDD.
    [[ "$EXTERNAL_HDD" =~ [Yy](es)? ]] && {
    echo "UUID=$EXTERNAL_UUID /mnt/harddisk $FORMAT_EXTERNAL defaults,uid=1000,gid=1000,umask=022,noatime,nofail 0 2" >> /etc/fstab ||
	    true; }
}

# We will create a generic hosts file with our username and local ip.
# Then we will append blacklisted hosts to the same file.
# Hosts are mentioned at the top of the script.
configure_hosts() {
    # Add the username variable as the hostname.
    sed -i "s/hostname=.*/hostname=\"$USERNAME\"/" /etc/conf.d/hostname

    # Generic localhost settings as shown on Gentoo Wiki.
    { echo "127.0.0.1	$USERNAME	localhost"
      echo "::1		$USERNAME	localhost"
    } > /etc/hosts

    # Append an empty line.
    echo " " >> /etc/hosts

    # Modify the blacklisted hosts and append to the file in a clean way.
    # We exclude Reddit as an example. Others can be similaryly excluded.
    # You can also later modify the file either by commands or manually.
    grep -oE '^0[^ ]+ [^ ]+' "$FILES_DIR"/blacklist_hosts.txt |
    grep -vF '0.0.0.0 0.0.0.0' |
    sed "/0.0.0.0 a.thumbs.redditmedia.com/,+66d" >> /etc/hosts
}

# Busybox UDHCPC is only 24kb and gets the job done in the fastest way possible.
# It's completely enough for the vast majority. The minority knows themselves.
# This function is not that important. It's just for removing everything on Busybox
# except UDHCPC which is the only module we need.
configure_udhcpc() {
    # Emerge busybox with savedconfig useflag (we have it on our package.use file
    # that we downloaded before).
    emerge sys-apps/busybox

    # Remove the generic config so we can apply ours.
    rm -f /etc/portage/savedconfig/sys-apps/busybox-*

    # Move the configuration file to its place.
    # This removes everything from Busybox but Udhcpc.
    move_file busybox-9999

    # Emerge busybox with the savedconfig again.
    emerge sys-apps/busybox

    # We need a directory to put udhcpc script in.
    mkdir -p "$UDHCPC_SCRIPT_DIR"

    # Move the very minimal init scripts for udhcpc.
    # I even stripped the non-needed parts of it (for home users) further.
    # You can check them from their URLs.
    move_file default.script
    move_file udhcpc

    # This version of udhcpc does not even touch /etc/resolv.conf
    # So we create it with the DNS we want. We can use Quad9 DNS
    # known for privacy, security and speed.
    { echo "nameserver 9.9.9.9"
      echo "nameserver 149.112.112.112"
    } > /etc/resolv.conf

    # The scripts for udhcpc should be executable.
    chmod +x "$UDHCPC_SCRIPT_DIR"/default.script
    chmod +x "$UDHCPC_INIT_DIR"/udhcpc

    # Activate udhcpc service and start it.
    rc-update add udhcpc default
    rc-service udhcpc start
}

# We will enable parallel start and disable everything related to hwclock
# since it's not needed. It's better to use local clock if you dual boot.
configure_openrc() {
    sed -i 's/.*clock_hc.*/clock_hctosys="NO"/
            s/.*clock_sys.*/clock_systohc="NO"/
	    s/.*clock=.*/clock="local"/' /etc/conf.d/hwclock

    sed -i 's/.*rc_parallel.*/rc_paralllel="yes"/
            s/.*rc_nocolor.*/rc_nocolor="yes"/
	    s/.*unicode.*/unicode="no"/' /etc/rc.conf

    # OpenRC Init does not provide tty services by default.
    # This instruction can be found on the Gentoo Wiki.
    # You can't boot into TTY without this.
    for n in $(seq 1 6); do ln -s /etc/init.d/agetty /etc/init.d/agetty.tty"$n"; rc-config add agetty.tty"$n" default; done
}

# We will create a user and a passwords in a non-interactive way. Since we
# already collected the name and pass variables. We will also configure doas (a
# minimal sudo replacement). Pipewire does not have an OpenRC service. So we launch
# gentoo-pipewire-launcher at boot instead.
configure_accounts() {
    # In order to add our users to certain groups we need to compile some packages.
    # Seatd is the most minimal seat manager for Wayland.
    # Dcron is the most minimal cronjob manager.
    emerge sys-auth/seatd sys-process/dcron media-video/wireplumber media-video/pipewire app-admin/doas

    # Change root password.
    echo "root:$PASSWORD" | chpasswd

    # Allow the users that are in the wheel group.
    echo "permit :wheel" > /etc/doas.conf

    # Doas won't ask password from the main user.
    echo "permit nopass keepenv :$USERNAME" >> /etc/doas.conf

    # Doas won't ask password when you mistakenly run commands with doas
    # while logged in as the root user.
    echo "permit nopass keepenv :root" >> /etc/doas.conf

    # We put our user on groups in order to use the listed features.
    useradd -mG wheel,audio,video,usb,input,portage,pipewire,seat,cron "$USERNAME"

    # Use the first collected variables to set the username and the password non-interactively.
    echo "$USERNAME:$PASSWORD" | chpasswd

    # Since we installed seatd, we need to add it to boottime in order to be able to login.
    rc-update add seatd default

    # Same for the cronjob manager.
    rc-update add dcron default
}

# We will disable Rsync Gentoo Repos and use git sync instead. It's much faster.
# We also enable other repositories in this step such as guru.
# Additionally, we will create our local repository.
configure_repos() {
    # We need these packages in order to use git sync and enable repos.
    emerge app-eselect/eselect-repository

    # Remove the default Gentoo repos.
    eselect repository remove gentoo

    # Add the new repos with git sync.
    eselect repository enable gentoo

    # Remove the files from default Gentoo repos.
    rm -rf /var/db/repos/gentoo

    # Add external repositories for librewolf brave and guru.
    eselect repository enable guru
    eselect repository add librewolf git https://codeberg.org/librewolf/gentoo.git
    eselect repository add brave-overlay git https://gitlab.com/jason.oliveira/brave-overlay.git

    # Add the local repository.
    eselect repository create "local"

    # We place the local repos we downloaded.
    mv -f "$FILES_DIR"/local/* "$LOCAL_REPO_DIR"

    # Create manifests for all local ebuilds.
    find "$LOCAL_REPO_DIR" -type f -name "*.ebuild" -exec ebuild {} manifest \;

    # Sync all of the repos using git.
    emaint sync -a
}

# This is very important. Without these modules started, you can't
# start Wayland compositors on Nvidia GPUs. This function will
# only run for machines with Nvidia GPUs.
add_nvidia_modules() {
    [[ "$GPU" =~ nvidia ]] && {
        mkdir -p /etc/modules-load.d
        { echo "nvidia"
          echo "nvidia_modeset"
          echo "nvidia_uvm"
          echo "nvidia_drm"
        } > /etc/modules-load.d/video.conf
    } || log_info b "Not using Nvidia. Skipping module setup."
}

# We have a list of dependencies (packages we want to install). We will install
# them together. This is the longest part since we install the browser and all
# other programs. Though we have Clang/Rust toolchain installed. So this
# shouldn't take too much time.
install_dependencies() {
    # Since we have our package list on each line we will modify the list as a
    # single line in order for the emerge command to work. We remove the comments
    # too.
    DEPLIST="$(sed -e 's/#.*$//' -e '/^$/d' "$FILES_DIR"/dependencies.txt | tr '\n' ' ')"

    # Now we can install the dependencies. This shouldn't have double quotes.
    # Because we want the arguments to be separated.
    emerge $DEPLIST
}

# We need to add the empty variables now since we have the $USERNAME.
# Then we need to update the associative array because it still
# has the empty ones.
initiate_new_vars() {
    USER_HOME="/home/$USERNAME"
    XDG_CONFIG_HOME="$USER_HOME/.config"
    ZDOTDIR="$XDG_CONFIG_HOME/zsh"
    LOCAL_BIN_DIR="$USER_HOME/.local/bin"
    WAL_VIM_DIR="$XDG_CONFIG_HOME/nvim/plugged/wal.vim/colors"

    update_associations
}

# We place the dotfiles we downloaded into the new user's home folder. .cache
# is for colors. Even though this defaul repo does not use pywal, and uses exclusive
# colors; it uses pywal's neovim plugin to create an easy colorscheme for neovim.
place_dotfiles() {
    mv -f "$FILES_DIR/dotfiles/.config" "$USER_HOME"
    mv -f "$FILES_DIR/dotfiles/.local" "$USER_HOME"
    mv -f "$FILES_DIR/dotfiles/.cache" "$USER_HOME"

    # Some files should be executable such as lf previews, user scripts.
    chmod +x "$LOCAL_BIN_DIR"/*
    chmod +x "$XDG_CONFIG_HOME"/lf/*
    chmod +x "$XDG_CONFIG_HOME"/dunst/warn.sh

    # We will use the lower-cased downloads folder. Do not forget
    # Changing settings to this folder on applications such as Browsers.
    mkdir -p "$USER_HOME/downloads"
}

# Gentoo has its own way to easily configure fonts. We basically enable the
# most modern and advanced settings for font rendering and rasterization.
configure_fonts() {
    eselect fontconfig disable 10-hinting-slight.conf
    eselect fontconfig disable 10-no-antialias.conf
    eselect fontconfig disable 10-sub-pixel-none.conf
    eselect fontconfig enable 10-hinting-full.conf
    eselect fontconfig enable 10-sub-pixel-rgb.conf
    eselect fontconfig enable 10-yes-antialias.conf
    eselect fontconfig enable 11-lcdfilter-default.conf
}

# Install the terminal file manager lf.
install_lf() {
    # This command will compile lf inside the go directory it creates.
    env CGO_ENABLED=0 go install -ldflags="-s -w" github.com/gokcehan/lf@latest

    # Move the compiled binary to the local binary directory.
    mv -f /root/go/bin/lf "$LOCAL_BIN_DIR"

    # Remove the unnecessary directory.
    rm -rf /root/go
}

# The below function will install TexLive with XeLaTeX support.
install_texlive() {
    # Download, configure and install texlive and some needed packages.
    tar -xzf "$FILES_DIR"/install-tl-unx.tar.gz -C "$FILES_DIR"

    # Extract directory name.
    TEX_DIR="$(find $FILES_DIR -maxdepth 1 -type d -name "install-tl-*")"

    update_associations

    move_file texlive.profile

    # Use the extracted directory name for running commands inside that directory.
    "$TEX_DIR"/install-tl -profile "$TEX_DIR"/texlive.profile

    # Install additional packages.
    tlmgr install apa7 biber biblatex geometry scalerel times xetex tools pgf hyperref infwarerr booktabs threeparttable caption fancyhdr endfloat
}

configure_shell() {
    # Create symlink for the shell profile file we downloaded.
    ln -s "$XDG_CONFIG_HOME/shell/profile" "$USER_HOME/.zprofile"

    # Change the default shell to Zsh.
    chsh --shell /bin/zsh "$USERNAME"

    # Link Dash to /bin/sh.
    ln -sfT /bin/dash /bin/sh

    # Move the plugins.
    move_file fzf-tab
    move_file zsh-autosuggestions
    move_file zsh-fast-syntax-highlighting
    move_file powerlevel10k
}

# Create an UEFI boot entry using efibootmgr.
create_boot_entry() {
    # efibootmgr uses separate disk and partition numbers.
    # we extract them using logic distinctively for nvme and sd disks.
    # For /dev/nvme0n1p1, DISK should output /dev/nvme0n1 and
    # For PARTITION it should output 1.
    emerge --oneshot sys-boot/efibootmgr

    DISK="$(echo "$PARTITION_BOOT" | grep -q 'nvme' && {
        echo "$PARTITION_BOOT" | sed -E 's/(nvme[0-9]+n[0-9]+).*/\1/'
    } || {
        echo "$PARTITION_BOOT" | sed -E 's/(sd[a-zA-Z]+).*/\1/'
    })"

    PARTITION="$(echo "$PARTITION_BOOT" | grep -q 'nvme' && {
        echo "$PARTITION_BOOT" | sed -E 's/.*nvme[0-9]+n[0-9]+p//'
    } || {
        echo "$PARTITION_BOOT" | sed -E 's/.*sd[a-zA-Z]*([0-9]+)$/\1/'
    })"

    # E.g: efibootmgr -c -d /dev/nvme0n1 -p 1 -L "gentoo_hyprland" -l '\EFI\BOOT\BOOTX64.EFI'
    efibootmgr -c -d /dev/"$DISK" -p "$PARTITION" -L "gentoo_hyprland" -l '\EFI\BOOT\BOOTX64.EFI'

    emerge --depclean
}

configure_neovim() {
    # Install Neovim plugins.
    doas -u "$USERNAME" nvim -u "$XDG_CONFIG_HOME/nvim/init.vim" +PlugInstall +qall

    # We need our neovim colors for root too.
    rm -rf "/root/.cache"
    cp -rf "$USER_HOME/.cache" /root/

    # Move the vim plugin file to use our terminal colors in neovim too.
    rm -f "$WAL_VIM_DIR/wal.vim"

    move_file "wal.vim"
}

clean_and_finalize() {
    rm -rf "$FILES_DIR" /var/log/* /var/cache/* /var/tmp/* /root/* "$USER_HOME"/.bash*

    # Make sure that the user owns their files.
    chown -R "$USERNAME":"$USERNAME" "$USER_HOME"
}

# Main function for the script. It informs us on every step with colored logs.
# So we know which step we are at, and if we succeeded. Since we have set -Eeo
# pipefail command enabled; the script only runs the success message if the
# command before succeeds.
main() {
    # Declare an associative array
    declare -A tasks

    # Define tasks with their descriptions and done messages on separate lines
    # and three tabs to increase readibility and ease of modifications.
    tasks[prepare_env]="Prepare the environment.
		        The environment prepared."

    tasks[select_timezone]="Select the Timezone.
    			    Timezone selected."

    tasks[select_gpu]="Select the GPU.
    		       GPU selected."

    tasks[collect_variables]="Collect the variables.
			      Variables collected."

    tasks[select_external_hdd]="Ask about External HDD.
    				External HDD set."

    tasks[check_first_vars]="Check the variables.
			     Variables good."

    tasks[collect_credentials]="Collect the credentials.
			        Credentials collected."

    tasks[check_credentials]="Check the credentials.
    			      Credentials good."

    tasks[sync_repos]="Sync the Gentoo Repositories.
		       Gentoo Repositories synced."

    tasks[retrieve_files]="Retrieve the files.
			   Files retrieved."

    tasks[check_files]="Control the files.
		        All files present."

    tasks[configure_locales]="Set the locales.
    			      Locales ready."

    tasks[configure_flags]="Set the make.conf flags.
    			    Make.conf flags ready."

    tasks[configure_portage]="Configure Portage.
    			      Portage configured."

    tasks[configure_useflags]="Configure useflags.
    			       Useflags ready."

    tasks[move_compiler_env]="Move the custom compiler env. files.
			      Custom compiler env files ready."

    tasks[update_system]="Update the system.
    			  System updated."

    tasks[build_clang_rust]="Build Clang/Rust Toolchain.
    			     Clang/Rust Toolchain ready."

    tasks[set_timezone]="Set the timezone.
    			 Timezone configured."

    tasks[set_cpu_microcode]="Configure CPU Microcode.
    			      CPU Microcode ready."

    tasks[set_linux_firmware]="Configure Linux Firmware.
    			       Linux Firmware ready."

    tasks[build_freetype]="Build Freetype.
    			   Freetype ready."

    tasks[build_linux]="Build the Linux Kernel.
			Linux Kernel ready."

    tasks[generate_fstab]="Generate FSTAB.
			   FSTAB ready."

    tasks[configure_hosts]="Configure Hosts file.
			    Hosts file ready."

    tasks[configure_udhcpc]="Configure UDHCPC.
			     UDHCPC ready."

    tasks[configure_openrc]="Configure OpenRC.
			     OpenRC ready."

    tasks[configure_accounts]="Configure Accounts.
			       Accounts ready."

    tasks[configure_repos]="Configure Repos.
			    Repos ready."

    tasks[add_nvidia_modules]="Adding nVidia Modules to bootlevel.
			       Nvidia modules added to bootlevel."

    tasks[install_dependencies]="Installing the dependencies.
			         All dependencies installed."

    tasks[initiate_new_vars]="Initiate new variables.
			      New variables ready."

    tasks[place_dotfiles]="Place the dotfiles.
			   Dotfiles ready."

    tasks[configure_fonts]="Configure font settings.
			    Fonts settings configured."

    tasks[install_lf]="Install LF file manager.
		       LF file manager ready."

    tasks[install_texlive]="Install TexLive.
		            TexLive ready."

    tasks[configure_shell]="Configure Shell
		            Shell ready."

    tasks[create_boot_entry]="Create UEFI Boot entry.
		              UEFI Boot Entry created."

    tasks[configure_neovim]="Configure Neovim
		             Neovim ready."

    tasks[clean_and_finalize]="Start clean-up and finish.
		        The Installation has finished. You can reboot with 'openrc-shutdown -r now'"

    # Indexed array to define the execution order.
    task_order=(prepare_env select_timezone select_gpu collect_variables select_external_hdd check_first_vars
                collect_credentials check_credentials sync_repos retrieve_files check_files configure_locales
		configure_flags configure_portage configure_useflags move_compiler_env update_system
		build_clang_rust set_timezone set_cpu_microcode set_linux_firmware build_freetype
		build_linux generate_fstab configure_hosts configure_udhcpc configure_openrc
		configure_accounts configure_repos add_nvidia_modules install_dependencies
		initiate_new_vars place_dotfiles configure_fonts install_lf install_texlive
		configure_shell create_boot_entry configure_neovim clean_and_finalize)

    TOTAL_TASKS=${#tasks[@]}
    TASK_NUMBER=1

    for function in "${task_order[@]}"; do
        # Split the task into description and done message
	description=${tasks[$function]}
	description=${description%%$'\n'*}

	done_message=$(echo "${tasks[$function]}" | tail -n 1 | sed 's/^[[:space:]]*//g')

        # Log the start of the task with the task number
        log_info b "$description"

        [[ $TASK_NUMBER -gt 8 ]] && {
	(sleep 60; while true; do
            log_info c "$description"
	    sleep 60
        done) &
        log_pid=$!; }

        # Call the function
        $function

	[[ $TASK_NUMBER -gt 8 ]] && kill $log_pid

        # Log the "Done" message with the task number
        log_info g "$done_message"

        # Increment the task number
        ((TASK_NUMBER++))
    done
}

main
