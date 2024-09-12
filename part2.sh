#!/usr/bin/env bash

# This script installs and configures a fully functing, completely
# configured Gentoo Linux system. The script should be run after chrooting.
# Run this script with: script -q -c 'bash part2.sh' -O "log.txt"

[[ "${UID}" == "0" ]] || {
        echo "Root login required"
        exit
}

set -Eeo pipefail

source "urls.txt"
source "filepaths.txt"

G='\e[1;92m' R='\e[1;91m' B='\e[1;94m'
P='\e[1;95m' Y='\e[1;93m' N='\033[0m'
C='\e[1;96m' W='\e[1;97m'

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

confirm_action() {
        while true; do
                echo -en "${G}Do you confirm? (y/n): ${N}"
                read -r user_input

                [[ "${user_input}" =~ ^[yY](es)?$|^[nN]o?$ ]] && break

                echo -e "${R}Invalid selection. Choose one of y, Yes, n, No.${N}"
        done

        [[ "${user_input}" =~ ^[yY](es)?$ ]] && return "0" || return "1"
}

handle_err() {
        stat="${?}"
        cmd="${BASH_COMMAND}"
        line="${LINENO}"
        loginf r "Line ${B}${line}${R}: cmd ${B}'${cmd}'${R} exited with ${B}\"${stat}\""
}

kill_bglog() {
        [ "${pidlog}" ] && kill "${pidlog}" > "/dev/null"
}

cleanup_logs() {
        [ -f "log.txt" ] && {
                sed -E -i 's/\r//g
                	s/.*RUNNING.*//g
                	s/.*Calculating.*//g
			s/>>> .*>>> //g
			s/Jobs: .*\.[0-9][0-9]//g
			/.*Installing.*/d
			/\* IMPORTANT:/,+9d
			s/>>> //g
			/Emerging/,/Completed/{/^$/d;}
			/Always study the list/,+11d
			/argument unused during/,+10d
			/Unable to find kernel/,+5d
			/Unable to calculate/d
			/clang as a system/,+9d
			/Package: /,/If you need support/d
			/Running pre-merge/d' "logfile.txt"

                sed -i -e :a -e '/^\n*$/N; /^\n$/D; ta' "logfile.txt"
                sed -i '/\x1b\[K$/d' "logfile.txt"
                sed -i -e :a -e '/^\n*$/N; /^\n$/D; ta' "logfile.txt"
        }
}

prepare_env() {
        source "/etc/profile"
        export PS1="(chroot) ${PS1}"
}

show_options_grid() {
        options=("${@}")

        for i in "${!options[@]}"; do
                printf "${Y}%2d) ${P}%-15s${N}" "$((i + 1))" "${options[i]}"
                (((i + 1) % 3 == 0)) && echo
        done

        ((${#options[@]} % 3 != 0)) && echo
}

is_musl() {
        eselect profile list 2>&1 | grep "\*" | grep -q "musl"
}

select_timezone() {
        is_musl && {
                emerge --info "sys-libs/timezone-data" > "/dev/null" ||
                        echo "Musl needs timezone-data. Need to sync and emerge."
                emerge --sync --quiet && emerge "sys-libs/timezone-data"
        }

        for i in "/usr/share/zoneinfo/"*; do
                [[ -d "${i}" ]] && [[ ! "${i##*/}" =~ Arctic|Antarctica|Etc ]] && regions+=("${i##*/}")
        done

        while true; do
                show_options_grid "${regions[@]}"

                echo -ne "${C}Select a region: ${N}"
                read -r region_choice

                selected_region=${regions[region_choice - 1]}
                echo -e "${G}Region selected: ${selected_region}${N}"

                confirm_action && break
                echo -e "${R}Declined. Restarting the process...${N}"
        done

        for i in "/usr/share/zoneinfo/${selected_region}"/*; do
                [[ -f "${i}" ]] && cities+=("${i##*/}")
        done

        while true; do
                show_options_grid "${cities[@]}"
                echo -ne "${C}Select a city: ${N}"
                read -r city_choice
                selected_city=${cities[city_choice - 1]}
                echo -e "${G}Timezone selected: ${selected_region}/${selected_city}${N}"

                confirm_action && break
                echo -e "${R}Selection canceled, restarting...${N}"
        done

        TIME_ZONE="${selected_region}/${selected_city}"
}

select_gpu() {
        valid_gpus=("via" "v3d" "vc4" "virgl" "vesa" "ast" "mga" "qxl" "i965" "r600" "i915" "r200" "r100" "r300" "lima" "omap" "r128" "radeon" "geode" "vivante" "nvidia" "fbdev" "dummy" "intel" "vmware" "glint" "tegra" "d3d12" "exynos" "amdgpu" "nouveau" "radeonsi" "virtualbox" "panfrost" "lavapipe" "freedreno" "siliconmotion")

        while true; do
                show_options_grid "${valid_gpus[@]}"
                echo -ne "${C}Select a GPU: ${N}"
                read -r gpu_choice
                selected_gpu=${valid_gpus[gpu_choice - 1]}
                echo -e "${G}GPU selected: ${selected_gpu}${N}"

                confirm_action && break
                echo -e "${R}Selection canceled, restarting...${N}"
        done
}

collect_variables() {
        PARTITION_ROOT="$(findmnt -n -o SOURCE /)"

        PARTITION_BOOT="$(lsblk -nlo NAME,RM,PARTTYPE |
                sed -n '/0\s*c12a7328-f81f-11d2-ba4b-00a0c93ec93b/ {s|^[^ ]*|/dev/&|; s| .*||p; q}')"

        UUID_ROOT="$(blkid -s UUID -o value "${PARTITION_ROOT}")"
        UUID_BOOT="$(blkid -s UUID -o value "${PARTITION_BOOT}")"
        PARTUUID_ROOT="$(blkid -s PARTUUID -o value "${PARTITION_ROOT}")"
}

select_external_hdd() {
        echo -e "${W}Do you have another partition you want to mount with boot? (y/n):${Y}"
        read -r EXTERNAL_HDD
        echo -e "${N}"

        [[ "${EXTERNAL_HDD}" =~ ^[yY](es)?$ ]] && {

                while true; do
                        echo -e "${W}Available Partitions:${N}"
                        IFS=$'\n'
                        for i in $(lsblk -lnfo NAME,FSTYPE,SIZE); do
                                [[ ! "${i}" =~ .*vfat.* ]] &&
                                        [[ ! "${i%% *}" =~ [a-z]$ ]] &&
                                        i="/dev/${i}" &&
                                        [[ ! "${i%% *}" == "${PARTITION_ROOT}" ]] &&
                                        [[ ! "${i%% *}" =~ ^.*n[0-9]$ ]] &&
                                        [[ ! "${i}" =~ ^[^\ ]+[\ ]+[^\ ]+$ ]] &&
                                        partitions+=("${i}")
                        done
                        unset IFS

                        for i in "${!partitions[@]}"; do
                                echo -e "${P}$((i + 1))) ${Y}${partitions[i]}${N}"
                        done

                        echo -ne "${W}Select a partition number: ${C}"
                        read -r partition_choice
                        partition_info="${partitions[partition_choice - 1]}"
                        PARTITION_EXTERNAL=${partition_info%% *}

                        read -r -a partition_details <<< "${partition_info}"
                        external_fs_type="${partition_details[1]}"

                        echo -ne "${W}Enter the mount path (e.g., /mnt/harddisk): ${C}"
                        read -r mount_path

                        echo -e "${G}Selected Partition: ${PARTITION_EXTERNAL}${N}"
                        echo -e "${G}Filesystem Type: ${external_fs_type}${N}"
                        echo -e "${G}Mount Path: ${mount_path}${N}"

                        confirm_action && break
                        echo -e "${R}Selection canceled, restarting...${N}"
                done

                EXTERNAL_UUID="$(blkid -s UUID -o value "${PARTITION_EXTERNAL}")" || true
        } || loginf b "No extra partitions specified. Skipping..."
}

check_first_vars() {
        lsblk "${PARTITION_BOOT}" > "/dev/null" 2>&1 || {
                loginf r "Partition ${PARTITION_BOOT} does not exist."
                exit "1"
        }

        DISK="${PARTITION_BOOT%[0-9]*}"
        DISK="${DISK%p}"

        fdisk -l "${DISK}" | grep -q "Disklabel type: gpt" || {
                loginf r "Your disk device is not 'GPT labeled'. Exit chroot first."
                loginf r "Use fdisk on your device without its partition: '/dev/nvme0n1'"
                loginf r "Delete every partition by typing 'd' and 'enter' first."
                loginf r "Type g (lower-cased) and enter to create a GPT label."
                loginf r "Then create 2 partitions for boot and root by typing 'n'."
                exit "1"
        }

        BOOT_PART_TYPE="$(lsblk -nlo PARTTYPE "${PARTITION_BOOT}")"

        [ "${BOOT_PART_TYPE}" = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ] || {
                loginf r "The boot partition does not have 'EFI System' type."
                loginf r "Use fdisk on your device '/dev/nvme0n1' without its partition."
                loginf r "Type 't' and enter. Select the related partition. Then make it 'EFI System'."
                exit "1"
        }

        BOOT_FS_TYPE="$(blkid -o value -s TYPE "${PARTITION_BOOT}")"

        [ "${BOOT_FS_TYPE}" = "vfat" ] || {
                loginf r "The boot partition should be formatted as 'vfat FAT32'."
                loginf r "Use 'mkfs.vfat -F 32 /dev/<your-partition>'."
                loginf r "You need 'sys-fs/dosfstools' for this operation."
                exit "1"
        }

        ROOT_PART_TYPE="$(lsblk -nlo PARTTYPE "${PARTITION_ROOT}")"

        [ "${ROOT_PART_TYPE}" = "0fc63daf-8483-4772-8e79-3d69d8477de4" ] || {
                loginf r "The root partition does not have 'Linux Filesystem' type."
                loginf r "Use fdisk on your device '/dev/nvme0n1' without its partition."
                loginf r "Type 't' and enter. Select the related partition. Then make it 'Linux Filesystem'."
                exit "1"
        }

        ROOT_FS_TYPE="$(blkid -o value -s TYPE "${PARTITION_ROOT}")"

        [[ "${ROOT_FS_TYPE}" =~ ^(ext4|f2fs)$ ]] || {
                loginf r "The root partition is not formatted with 'ext4' or 'f2fs'."
                loginf r "Use 'mkfs.ext4 /dev/<your-partition>'."
                loginf r "Or check the documentation for mkfs.f2fs"
                exit "1"
        }

        TZ_FILE="/usr/share/zoneinfo/${TIME_ZONE}"

        [ -f "${TZ_FILE}" ] || {
                loginf r "The timezone ${TIME_ZONE} is invalid or does not exist."
                exit "1"
        }

        [ "${UUID_ROOT}" ] && [ "${UUID_BOOT}" ] && [ "${PARTUUID_ROOT}" ] || {
                loginf r "Critical partition information is missing."
                exit "1"
        }

        [[ ${valid_gpus[*]} =~ ${selected_gpu} && "${selected_gpu}" =~ [^[:space:]] ]] || {
                loginf r "Invalid GPU. Please enter a valid GPU."
                exit "1"
        }
}

collect_credentials() {
        echo -e "${W}Enter the Username:${Y}"
        read -r USERNAME
        echo -e "${W}Enter the Password:${Y}"
        read -r -s PASSWORD
        echo -e "${W}Confirm the Password:${Y}"
        read -r -s PASSWORD2

        echo ""
        echo -e "${N}"
}

check_credentials() {
        [[ "${USERNAME}" =~ ^[a-zA-Z0-9_-]+$ ]] || {
                loginf r "Invalid username. Only alphanumeric characters, underscores, and dashes are allowed."
                exit "1"
        }

        [ "${PASSWORD}" = "${PASSWORD2}" ] && [ "${PASSWORD}" ] || {
                loginf r "Passwords do not match or are empty."
                exit "1"
        }
}

sync_repos() {
        emerge --sync --quiet
        emerge --quiet-build "dev-vcs/git"
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
        associate_f "package.use" "${URL_PACKAGE_USE}" "${PORTAGE_DIR}"
        associate_f "package.accept_keywords" "${URL_ACCEPT_KEYWORDS}" "${PORTAGE_DIR}"
        associate_f "package.env" "${URL_PACKAGE_ENV}" "${PORTAGE_DIR}"
        associate_f "use.mask" "${URL_USE_MASK}" "${PORTAGE_PROFILE_DIR}"
        associate_f "package.unmask" "${URL_PACKAGE_UNMASK}" "${PORTAGE_PROFILE_DIR}"
        associate_f ".config" "${URL_KERNEL_CONFIG}" "${LINUX_DIR}"
        associate_f "clang_o3_lto" "${URL_CLANG_O3_LTO}" "${PORTAGE_ENV_DIR}"
        associate_f "clang_o3_lto_fpic" "${URL_CLANG_O3_LTO_FPIC}" "${PORTAGE_ENV_DIR}"
        associate_f "gcc_o3_lto" "${URL_GCC_O3_LTO}" "${PORTAGE_ENV_DIR}"
        associate_f "gcc_o3_nolto" "${URL_GCC_O3_NOLTO}" "${PORTAGE_ENV_DIR}"
        associate_f "gcc_o3_lto_ffatlto" "${URL_GCC_O3_LTO_FFATLTO}" "${PORTAGE_ENV_DIR}"
        associate_f "fzf-tab" "${URL_FZF_TAB}" "${ZDOTDIR}"
        associate_f "zsh-autosuggestions" "${URL_ZSH_AUTOSUGGESTIONS}" "${ZDOTDIR}"
        associate_f "fast-syntax-highlighting" "${URL_SYNTAX_HIGHLIGHT}" "${ZDOTDIR}"
        associate_f "texlive.profile" "${URL_TEXLIVE_PROFILE}" "${TEX_DIR}"
        associate_f "dependencies.txt" "${URL_DEPENDENCIES_TXT}"
        associate_f "dotfiles" "${URL_DOTFILES}"
        associate_f "busybox" "${URL_BUSYBOX_CONFIG}" "${BUSYBOX_CONFIG_DIR}"
        associate_f "default.script" "${URL_DEFAULT_SCRIPT}" "${UDHCPC_SCRIPT_DIR}"
        associate_f "udhcpc" "${URL_UDHCPC_INIT}" "${UDHCPC_INIT_DIR}"
        associate_f "udhcpc.sh" "${URL_UDHCPC_SH}" "${UDHCPC_SH_DIR}"
        associate_f "install-tl-unx.tar.gz" "${URL_TEXLIVE_INSTALL}"
}

update_associations

move_file() {
        key="${1}"
        read -r _ download_path final_destination <<< "${associate_files[${key}]}"

        mv -f "${download_path}" "${final_destination}"
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
        source="${1}"
        dest="${2}"

        [ -d "${dest}" ] && {
                loginf b "Directory ${dest} already exists, skipping download."
                return
        }

        [ -f "${dest}" ] && {
                loginf b "File ${dest} already exists, skipping download."
                return
        }

        [[ "${source}" == *".git" ]] && {
                git clone "${source}" "${dest}" > "/dev/null" 2>&1
                return
        }

        curl -L "${source}" -o "${dest}" > "/dev/null" 2>&1
}

retrieve_files() {
        mkdir -p "${FILES_DIR}"
        total="${#associate_files[@]}"
        current="0"

        echo -ne "\033[?25l"

        for key in "${!associate_files[@]}"; do
                current="$((current + 1))"
                progs "${total}" "${current}"

                read -r source dest _ <<< "${associate_files[${key}]}"
                download_file "${source}" "${dest}"
        done

        echo ""

        echo -e "\033[?25h"
}

check_files() {
        for key in "${!associate_files[@]}"; do
                read -r _ f _ <<< "${associate_files["${key}"]}"
                [[ -s "${f}" ]] || [[ -d "${f}" ]] || {
                        loginf r "${f} is missing."
                        kill -9 "0"
                }
        done
}

renew_env() {
        env-update && source "/etc/profile" && export PS1="(chroot) ${PS1}"
}

configure_locales() {
        is_musl && return "0"

        sed -i "/#en_US.UTF/ s/#//g" "/etc/locale.gen"

        locale-gen

        eselect locale set "en_US.utf8"

        echo 'LC_COLLATE="C.UTF-8"' >> "/etc/env.d/02locale"

        renew_env
}

configure_flags() {
        sed -i '/COMMON_FLAGS=/ c\COMMON_FLAGS="-march=native -O2 -pipe"
		/^FFLAGS/ a\LDFLAGS="-Wl,-O2 -Wl,--as-needed"
		/^FFLAGS/ a\RUSTFLAGS="-C debuginfo=0 -C codegen-units=1 -C target-cpu=native -C opt-level=3"' "/etc/portage/make.conf"

        echo "" >> "/etc/portage/make.conf"

        emerge --oneshot "app-portage/cpuid2cpuflags"
        cpuid2cpuflags | sed 's/: /="/; s/$/"/' >> "/etc/portage/make.conf"

        echo "" >> "/etc/portage/make.conf"

        cat <<- EOF >> "/etc/portage/make.conf"
	ACCEPT_KEYWORDS="~amd64"
	RUBY_TARGETS="ruby33"
	RUBY_SINGLE_TARGET="ruby33"
	LUA_TARGETS="lua5-4"
	LUA_SINGLE_TARGET="lua5-4"
	EOF
}

configure_portage() {
        {
                echo ""
                echo 'ACCEPT_LICENSE="*"'

                echo "VIDEO_CARDS=\"${selected_gpu}\""

                echo "MAKEOPTS=\"-j$(($(nproc) - 2)) -l$(($(nproc) - 1))\""

                is_musl || echo 'PORTAGE_SCHEDULING_POLICY="idle"'

                echo "EMERGE_DEFAULT_OPTS=\"--jobs=1 --load-average=$(($(nproc) - 1)) --keep-going --verbose --quiet-build --with-bdeps=y --complete-graph=y --deep\""

                echo 'USE="-* minimal wayland pipewire clang native-symlinks lto pgo jit xs orc threads asm openmp libedit custom-cflags system-man system-libyaml system-lua system-bootstrap system-llvm system-lz4 system-sqlite system-ffmpeg system-icu system-av1 system-harfbuzz system-jpeg system-libevent system-librnp system-libvpx system-png system-python-libs system-webp system-ssl system-zlib system-boost"'

                echo 'FEATURES="fixlafiles unmerge-orphans nodoc noinfo notitles parallel-install parallel-fetch clean-logs"'

                echo 'PORTAGE_COMPRESS_EXCLUDE_SUFFIXES="[1-9] n [013]p [1357]ssl"
PORTAGE_COMPRESS=gzip'
        } >> "/etc/portage/make.conf"
}

remove_dirs() {
        rm -rf "/etc/portage/package.use"
        rm -rf "/etc/portage/package.accept_keywords"
}

configure_useflags() {
        remove_dirs

        move_file "package.use"
        move_file "package.accept_keywords"
        move_file "use.mask"
        move_file "package.unmask"
}

move_compiler_env() {
        mkdir -p "${PORTAGE_ENV_DIR}"
        move_file "clang_o3_lto"
        move_file "clang_o3_lto_fpic"
        move_file "gcc_o3_lto"
        move_file "gcc_o3_nolto"
        move_file "gcc_o3_lto_ffatlto"
}

update_system() {
        renew_env

        emerge "app-text/mandoc"

        USE="reference -pigz" emerge --update --newuse @world

        CLEAN_DELAY="0" emerge --depclean --verbose=n -q

        emerge -e @world

        emerge @preserved-rebuild

        CLEAN_DELAY="0" emerge --depclean --verbose=n -q

        renew_env
}

build_clang_rust() {
        NEW_MAKEOPTS="$(("$(nproc)" * 2 / 3))"

        MAKEOPTS="-j${NEW_MAKEOPTS} -l${NEW_MAKEOPTS}" emerge "dev-lang/rust" "sys-devel/clang"

        move_file "package.env"

        renew_env

        MAKEOPTS="-j${NEW_MAKEOPTS} -l$(("${NEW_MAKEOPTS}" + 1))" emerge --oneshot "sys-devel/clang" "dev-libs/jsoncpp" "dev-libs/libuv" "sys-devel/llvm" "sys-devel/llvm-common" "sys-devel/llvm-toolchain-symlinks" "sys-devel/lld" "sys-libs/libunwind" "sys-libs/compiler-rt" "sys-libs/compiler-rt-sanitizers" "sys-devel/clang-common" "dev-build/cmake" "sys-devel/clang-runtime" "sys-devel/clang-toolchain-symlinks" "sys-libs/libomp" "dev-lang/rust" "dev-lang/perl" "dev-lang/python" "app-alternatives/ninja" "dev-build/samurai" "dev-libs/libedit"

        CLEAN_DELAY="0" emerge --depclean --verbose=n -q

        is_musl || {
                emerge "sys-devel/gcc"
                renew_env
                emerge "sys-libs/glibc" "sys-devel/binutils"
        } || loginf b "The user has the Musl profile. Skipping GCC setup."

        emerge -e @world --exclude 'sys-devel/clang dev-libs/jsoncpp dev-libs/libuv sys-devel/llvm sys-devel/llvm common sys-devel/llvm-toolchain-symlinks sys-devel/lld sys-libs/llvm-libunwind sys-libs/compiler-rt sys-libs/compiler-rt-sanitizers sys-devel/clang-common dev-build/cmake sys-devel/clang-runtime sys-devel/clang-toolchain-symlinks sys-libs/libomp dev-lang/rust dev-lang/perl dev-lang/python app-alternatives/ninja dev-build/samurai dev-libs/libedit sys-devel/gcc sys-libs/glibc sys-devel/binutils sys-libs/libcxx sys-libs/libcxxabi'
}

set_timezone() {
        rm -f "/etc/localtime"

        echo "${TIME_ZONE}" > "/etc/timezone"

        emerge --config "sys-libs/timezone-data"
}

set_cpu_microcode() {
        echo 'MICROCODE_SIGNATURES="-S"' >> "/etc/portage/make.conf"

        emerge "sys-firmware/intel-microcode"

        SIGNATURE="$(iucode_tool -S 2>&1 | grep -o "0x0.*$")"

        sed -i "/MICROCODE/ s/-S/-s ${SIGNATURE}/" "/etc/portage/make.conf"

        emerge "sys-firmware/intel-microcode"
}

set_linux_firmware() {
        emerge "sys-kernel/linux-firmware"

        [ "${selected_gpu}" = "nvidia" ] && {
                emerge --oneshot "sys-apps/pciutils"

                GPU_CODE="$(lspci | grep -i 'vga\|3d\|2d' |
                        sed -n '/NVIDIA Corporation/{s/.*NVIDIA Corporation \([^ ]*\).*/\L\1/p}' |
                        sed 's/m$//')"

                sed -i '/^nvidia\/'"${GPU_CODE}"'/!d' "/etc/portage/savedconfig/sys-kernel"/linux-firmware-*

        } || loginf b "Not using Nvidia... Skipping the debloating process for Linux Firmware."
}

build_freetype() {
        USE="-harfbuzz" emerge --oneshot "media-libs/freetype"

        emerge --oneshot "media-libs/freetype"
}

build_linux() {
        emerge "sys-kernel/gentoo-sources" "app-arch/lz4"

        move_file ".config"

        sed -i "/^CONFIG_CMDLINE=.*/ c\CONFIG_CMDLINE=\"root=PARTUUID=${PARTUUID_ROOT} init=/sbin/openrc-init\"" "${LINUX_DIR}/.config"

        [ "${selected_gpu}" = "nvidia" ] && sed -i "/^CONFIG_CMDLINE=/
		s/\"$/ nvidia_drm.modeset=1 nvidia_drm.fbdev=1\"/" \
                "${LINUX_DIR}/.config"

        MICROCODE_PATH="$(iucode_tool -S -l /lib/firmware/intel-ucode/* 2>&1 |
                grep -o "intel-ucode/.*")"

        THREAD_NUM="$(nproc)"

        sed -i "/CONFIG_EXTRA_FIRMWARE=/ s|=.*|=\"${MICROCODE_PATH}\"|
            /CONFIG_NR_CPUS=/ s|=.*|=${THREAD_NUM}|" "${LINUX_DIR}/.config"

        export LLVM="1" LLVM_IAS="1" CFLAGS="-O3 -march=native -pipe" KCFLAGS="-O3 -march=native -pipe"

        make -C "${LINUX_DIR}" olddefconfig

        make -C "${LINUX_DIR}" -j"$(nproc)" -l"$(($(nproc) + 1))"

        [ "${selected_gpu}" = "nvidia" ] && {
                emerge "x11-drivers/nvidia-drivers"
                echo "options nvidia NVreg_UsePageAttributeTable=1" >> "/etc/modprobe.d/nvidia.conf"
        } || loginf b "Not using Nvidia... Skipping..."

        emerge "sys-kernel/linux-firmware"

        make -C "${LINUX_DIR}" modules_install

        mount "${PARTITION_BOOT}" "/boot"

        mkdir -p "/boot/EFI/BOOT"

        cp -f "${NEW_KERNEL}" "${KERNEL_PATH}"
}

generate_fstab() {
        echo "UUID=${UUID_BOOT} /boot vfat defaults,noatime 0 2" > "/etc/fstab"

        echo "UUID=${UUID_ROOT} / ${ROOT_FS_TYPE} defaults,noatime 0 1" >> "/etc/fstab"

        [[ "${EXTERNAL_HDD}" =~ ^[yY](es)?$ ]] && {
                [ "${external_fs_type}" = "ntfs" ] && external_fs_type="ntfs3"
                echo "UUID=${EXTERNAL_UUID} ${mount_path} ${external_fs_type} defaults,uid=1000,gid=1000,noatime,nofail 0 2" >> "/etc/fstab"
        } || true
}

configure_hosts() {
        sed -i "s/hostname=.*/hostname=\"${USERNAME}\"/" "/etc/conf.d/hostname"

        {
                echo "127.0.0.1	${USERNAME}	localhost"
                echo "::1		${USERNAME}	localhost"
        } > "/etc/hosts"

        echo " " >> "/etc/hosts"

        grep -oE '^0[^ ]+ [^ ]+' "${FILES_DIR}/blacklist_hosts.txt" |
                grep -vF '0.0.0.0 0.0.0.0' |
                sed "/0.0.0.0 a.thumbs.redditmedia.com/,+66d" >> "/etc/hosts"
}

configure_udhcpc() {
        emerge "sys-apps/busybox"

        rm -f "/etc/portage/savedconfig/sys-apps"/busybox-*

        move_file "busybox"

        emerge "sys-apps/busybox"

        mkdir -p "${UDHCPC_SCRIPT_DIR}"

        move_file "default.script"
        move_file "udhcpc"
        move_file "udhcpc.sh"

        {
                echo "nameserver 9.9.9.9"
                echo "nameserver 149.112.112.112"
        } > "/etc/resolv.conf"

        chmod +x "${UDHCPC_SCRIPT_DIR}/default.script"
        chmod +x "${UDHCPC_INIT_DIR}/udhcpc"
        chmod +x "${UDHCPC_SH_DIR}/udhcpc.sh"

        rc-update add "udhcpc" default
        rc-service "udhcpc" start
}

configure_openrc() {
        sed -i 's/.*clock_hc.*/clock_hctosys="NO"/
            s/.*clock_sys.*/clock_systohc="NO"/
	    s/.*clock=.*/clock="local"/' "/etc/conf.d/hwclock"

        sed -i 's/.*rc_parallel.*/rc_paralllel="yes"/
            s/.*rc_nocolor.*/rc_nocolor="yes"/
	    s/.*unicode.*/unicode="no"/' "/etc/rc.conf"

        for n in $(seq "1" "6"); do
                ln -s "/etc/init.d/agetty" "/etc/init.d/agetty.tty${n}"
                rc-config add "agetty.tty${n}" default
        done
}

configure_accounts() {
        emerge "sys-auth/seatd" "sys-process/dcron" "media-video/wireplumber" "media-video/pipewire" "app-admin/doas" "net-p2p/transmission"

        echo "root:${PASSWORD}" | chpasswd

        echo "permit :wheel" > "/etc/doas.conf"

        echo "permit nopass keepenv :${USERNAME}" >> "/etc/doas.conf"

        echo "permit nopass keepenv :root" >> "/etc/doas.conf"

        useradd -mG wheel,audio,video,usb,input,portage,pipewire,seat,cron,transmission "${USERNAME}"

        echo "${USERNAME}:${PASSWORD}" | chpasswd

        rc-update add "seatd" default

        rc-update add "dcron" default
}

configure_repos() {
        emerge "app-eselect/eselect-repository"

        eselect repository remove "gentoo" && rm -rf "/var/db/repos/gentoo"

        eselect repository enable "gentoo"

        eselect repository enable "guru"
        eselect repository add "librewolf" git "https://codeberg.org/librewolf/gentoo.git"
        eselect repository add "brave-overlay" git "https://gitlab.com/jason.oliveira/brave-overlay.git"
        eselect repository add "emrakyz" git "https://github.com/emrakyz/local.git"

        emaint sync -a

        emerge --oneshot "sys-apps/portage"
}

add_nvidia_modules() {
        [[ "${selected_gpu}" == "nvidia" ]] && {
                mkdir -p "/etc/modules-load.d"

                {
                        echo "nvidia"
                        echo "nvidia_modeset"
                        echo "nvidia_uvm"
                        echo "nvidia_drm"
                } > "/etc/modules-load.d/video.conf"

        } || loginf b "Not using Nvidia. Skipping module setup."
}

install_dependencies() {
        DEPLIST="$(sed -e 's/#.*$//' -e '/^$/d' "${FILES_DIR}/dependencies.txt" | tr '\n' ' ')"

        emerge ${DEPLIST}
}

initiate_new_vars() {
        USER_HOME="/home/${USERNAME}"
        XDG_CONFIG_HOME="${USER_HOME}/.config"
        ZDOTDIR="${XDG_CONFIG_HOME}/zsh"
        LOCAL_BIN_DIR="${USER_HOME}/.local/bin"

        update_associations
}

place_dotfiles() {
        mv -f "${FILES_DIR}/dotfiles/.config" "${USER_HOME}"
        mv -f "${FILES_DIR}/dotfiles/.local" "${USER_HOME}"
        mv -f "${FILES_DIR}/dotfiles/.cache" "${USER_HOME}"

        chmod +x "${LOCAL_BIN_DIR}"/*
        chmod +x "${XDG_CONFIG_HOME}/lf"/*
        chmod +x "${XDG_CONFIG_HOME}/dunst/warn.sh"

        mkdir -p "${USER_HOME}/downloads"
}

configure_fonts() {
        eselect fontconfig disable "10-hinting-slight.conf"
        eselect fontconfig disable "10-no-antialias.conf"
        eselect fontconfig disable "10-sub-pixel-none.conf"
        eselect fontconfig enable "10-hinting-full.conf"
        eselect fontconfig enable "10-sub-pixel-rgb.conf"
        eselect fontconfig enable "10-yes-antialias.conf"
        eselect fontconfig enable "11-lcdfilter-default.conf"
}

install_lf() {
        env CGO_ENABLED="0" go install -ldflags="-s -w" "github.com/gokcehan/lf@latest"

        mv -f "/root/go/bin/lf" "${LOCAL_BIN_DIR}"

        rm -rf "/root/go"
}

install_texlive() {
        tar -xzf "${FILES_DIR}/install-tl-unx.tar.gz" -C "${FILES_DIR}"

        TEX_DIR="$(find "${FILES_DIR}" -maxdepth "1" -type "d" -name "install-tl-*")"

        update_associations

        move_file "texlive.profile"

        "${TEX_DIR}/install-tl" -profile "${TEX_DIR}/texlive.profile"

        tlmgr install apa7 biber biblatex geometry scalerel times \
                xetex tools pgf hyperref infwarerr booktabs \
                threeparttable caption fancyhdr endfloat
}

configure_shell() {
        ln -s "${XDG_CONFIG_HOME}/shell/profile" "${USER_HOME}/.zprofile"

        chsh --shell "/bin/zsh" "${USERNAME}"

        ln -sfT "/bin/dash" "/bin/sh"

        move_file "fzf-tab"
        move_file "zsh-autosuggestions"
        move_file "fast-syntax-highlighting"
        move_file "powerlevel10k"
}

create_boot_entry() {
        emerge --oneshot "sys-boot/efibootmgr"

        DISK="$(echo "${PARTITION_BOOT}" | grep -q 'nvme' && {
                echo "${PARTITION_BOOT}" | sed -E 's/(nvme[0-9]+n[0-9]+).*/\1/'
        } || {
                echo "${PARTITION_BOOT}" | sed -E 's/(sd[a-zA-Z]+).*/\1/'
        })"

        PARTITION="$(echo "${PARTITION_BOOT}" | grep -q 'nvme' && {
                echo "${PARTITION_BOOT}" | sed -E 's/.*nvme[0-9]+n[0-9]+p//'
        } || {
                echo "${PARTITION_BOOT}" | sed -E 's/.*sd[a-zA-Z]*([0-9]+)$/\1/'
        })"

        efibootmgr -c -d "${DISK}" -p "${PARTITION}" -L "gentoo_hyprland" -l '\EFI\BOOT\BOOTX64.EFI'

        CLEAN_DELAY="0" emerge --depclean --verbose=n -q
}

configure_neovim() {
        chown -f -R "${USERNAME}":"${USERNAME}" "${USER_HOME}"
        doas -u "${USERNAME}" nvim -u "${XDG_CONFIG_HOME}/nvim/init.vim" +PlugInstall +qall
}

add_mirrors() {
        emerge "app-portage/mirrorselect"

        mirrorselect -s12 -b10 -q -o "temp.conf"

        while IFS= read -r line; do
                links+=("${line}")
        done < <(grep -Eo '(ftp|http)s?://[^ "]+' "temp.conf")

        exec 3> "temp2.conf"

        echo -n 'GENTOO_MIRRORS="' >&3

        num_links=${#links[@]}

        for ((i = 0; i < num_links; i++)); do
                ((i < num_links - 1)) && {
                        echo -n "${links[i]} \\" >&3
                        echo >&3
                        echo -ne '\t' >&3
                } || echo -n "${links[i]}\"" >&3
        done

        exec 3>&-

        echo "" >> "/etc/portage/make.conf"
        cat "temp2.conf" >> "/etc/portage/make.conf"

        rm -f "temp.conf" "temp2.conf"
        CLEAN_DELAY="0" emerge --depclean "app-portage/mirrorselect" -q --verbose=n
}

clean_and_finalize() {
        rm -rf "${FILES_DIR}" "/var/log"/* "/var/cache"/* "/var/tmp"/* "/root/"* "${USER_HOME}"/.bash*

        emerge @preserved-rebuild
        emerge --depclean

        chown -f -R "${USERNAME}":"${USERNAME}" "${USER_HOME}"
}

main() {
        declare -A tsks

        tsks["prepare_env"]="Prepare the environment.
		        The environment prepared."

        tsks["select_timezone"]="Select the Timezone.
    			    Timezone selected."

        tsks["select_gpu"]="Select the GPU.
    		       GPU selected."

        tsks["collect_variables"]="Collect the variables.
			      Variables collected."

        tsks['select_external_hdd']="Ask about External HDD.
    				External HDD set."

        tsks["check_first_vars"]="Check the variables.
			     Variables good."

        tsks["collect_credentials"]="Collect the credentials.
			        Credentials collected."

        tsks["check_credentials"]="Check the credentials.
    			      Credentials good."

        tsks["sync_repos"]="Sync the Gentoo Repositories.
		       Gentoo Repositories synced."

        tsks["retrieve_files"]="Retrieve the files.
			   Files retrieved."

        tsks["check_files"]="Control the files.
		        All files present."

        tsks["configure_locales"]="Set the locales.
    			      Locales ready."

        tsks["configure_flags"]="Set the make.conf flags.
    			    Make.conf flags ready."

        tsks["configure_portage"]="Configure Portage.
    			      Portage configured."

        tsks["configure_useflags"]="Configure useflags.
    			       Useflags ready."

        tsks["move_compiler_env"]="Move the custom compiler env. files.
			      Custom compiler env files ready."

        tsks["update_system"]="Update the system.
    			  System updated."

        tsks["build_clang_rust"]="Build Clang/Rust Toolchain.
    			     Clang/Rust Toolchain ready."

        tsks["set_timezone"]="Set the timezone.
    			 Timezone configured."

        tsks["set_cpu_microcode"]="Configure CPU Microcode.
    			      CPU Microcode ready."

        tsks["set_linux_firmware"]="Configure Linux Firmware.
    			       Linux Firmware ready."

        tsks["build_freetype"]="Build Freetype.
    			   Freetype ready."

        tsks["build_linux"]="Build the Linux Kernel.
			Linux Kernel ready."

        tsks["generate_fstab"]="Generate FSTAB.
			   FSTAB ready."

        tsks["configure_hosts"]="Configure Hosts file.
			    Hosts file ready."

        tsks["configure_udhcpc"]="Configure UDHCPC.
			     UDHCPC ready."

        tsks["configure_openrc"]="Configure OpenRC.
			     OpenRC ready."

        tsks["configure_accounts"]="Configure Accounts.
			       Accounts ready."

        tsks["configure_repos"]="Configure Repos.
			    Repos ready."

        tsks["add_nvidia_modules"]="Adding nVidia Modules to bootlevel.
			       Nvidia modules added to bootlevel."

        tsks["install_dependencies"]="Installing the dependencies.
			         All dependencies installed."

        tsks["initiate_new_vars"]="Initiate new variables.
			      New variables ready."

        tsks["place_dotfiles"]="Place the dotfiles.
			   Dotfiles ready."

        tsks["configure_fonts"]="Configure font settings.
			    Fonts settings configured."

        tsks["install_lf"]="Install LF file manager.
		       LF file manager ready."

        tsks["install_texlive"]="Install TexLive.
		            TexLive ready."

        tsks["configure_shell"]="Configure Shell
		            Shell ready."

        tsks["create_boot_entry"]="Create UEFI Boot entry.
		              UEFI Boot Entry created."

        tsks["configure_neovim"]="Configure Neovim
		             Neovim ready."

        tsks["add_mirrors"]="Add Portage mirrors.
		             Mirrors added."

        tsks["clean_and_finalize"]="Start clean-up and finish.
		        The Installation has finished. You can reboot with 'openrc-shutdown -r now'"

        tsk_ord=("prepare_env" "select_timezone" "select_gpu" "collect_variables"
                "select_external_hdd" "check_first_vars" "collect_credentials" "check_credentials"
                "sync_repos" "retrieve_files" "check_files" "configure_locales" "configure_flags"
                "configure_portage" "configure_useflags" "move_compiler_env" "update_system"
                "build_clang_rust" "set_timezone" "set_cpu_microcode" "set_linux_firmware"
                "build_freetype" "build_linux" "generate_fstab" "configure_hosts" "configure_udhcpc"
                "configure_openrc" "configure_accounts" "configure_repos" "add_nvidia_modules"
                "install_dependencies" "initiate_new_vars" "place_dotfiles" "configure_fonts"
                "install_lf" "install_texlive" "configure_shell" "create_boot_entry"
                "configure_neovim" "add_mirrors" "clean_and_finalize")

        ALLTSK="${#tsks[@]}"
        TSKNO="1"

        trap 'handle_err; kill_bglog; cleanup_logs' ERR RETURN
        trap 'kill_bglog; cleanup_logs' EXIT INT QUIT TERM

        for funct in "${tsk_ord[@]}"; do
                descript="${tsks[${funct}]}"
                descript="${descript%%$'\n'*}"

                msgdone="$(echo "${tsks[${funct}]}" | tail -n "1" | sed 's/^[[:space:]]*//g')"

                loginf b "${descript}"

                [[ "${TSKNO}" -gt "8" ]] && {
                        (
                                sleep "240"
                                while true; do
                                        loginf c "${descript}"
                                        sleep "240"
                                done
                        ) &
                        pidlog="${!}"
                }

                "${funct}"
                loginf g "${msgdone}"

                [[ "${TSKNO}" -eq "${ALLTSK}" ]] && {
                        loginf g "All tsks completed."
                        kill "${pidlog}" 2> "/dev/null" || true
                        kill "0" > "/dev/null"
                }

                kill "${pidlog}" 2> "/dev/null" || true

                ((TSKNO++))
        done
}

main
