#!/bin/zsh

# contains lots of checks to minimize the work effort in case anything
# goes wrong in the script and you don´t want to start from scratch

SYSROOT="/mnt"
BOOT_LABEL_PREFIX="BOOT"
ROOT_LABEL_PREFIX="linux"
# when systemd is running in the initrd, the / partition may be encrypted in
# LUKS format. In this case, a device mapper device is set up under the name
# /dev/mapper/root, so this name should probably be always 'root'
MAPPER_NAME_PREFIX="root"

#The subvolumes are inspired by
# https://en.opensuse.org/SDB:BTRFS
# primary arguments for these subvolumes are, that they shall not be included in
# snapshots and not be rolled back. Underscores _ in subvolume names will be
# replaced by / to determine the mount point

# this layout has all subvolumes below the root subvolume. auto-mount is not possible, because even

subvolumes=(
  @           # root directory
  @home       # user home
  @opt        # third party software
  @root       # root user home
  @srv        # for web servers
  @tmp        # temporary files
  @usr_local  # manually installed programs
  @var        # logs, temp files
  @.snapshots # to store the btrfs snapshots
)

mount_options="noatime,compress=zstd:1"

kernel_cmdline=(
  quiet                        # suppresses output messagess
  splash                       # enables plymouth for nice encryption password prompt
  "rootflags=${mount_options}" # mount options for rootfs
)

mkinitcpio_hooks=(
  base          #
  systemd       #
  systemd-ukify # contains neccessary kernel-install hooks for uki generation, see https://bugs.archlinux.org/task/80240#comment223638
  plymouth      # boot splash and unlock screen
  autodetect    #
  modconf       #
  kms           # must not be included when using NVIDIA driver
  keyboard      # so drive encryption password can be entered
  sd-vconsole   # only needed when encryption pw shall be entered in a different keymap than us
  block         #
  sd-encrypt    # for decryption
  filesystems   #
  fsck          #
)

services=(
  # File systems
  fstrim.timer # Periodically trim file systems…
  #"btrfs-scrub@$(systemd-escape -p /).timer" # scrub root filesystem…

  # Core system services
  systemd-boot-update.service # Update boot loader automatically
  systemd-timesyncd.service   # Time sync

  # Networking services
  NetworkManager.service # Network manager for desktops

  # Pacman infrastructure
  reflector.service # Update fastest pacman mirror
)

# can be set from command line
FORCE=false
ENCRYPT=true

select_entry_from_array() {
  local array=("$@")
  n_entries=${#array[@]}
  if [[ "$n_entries" == 1 ]]; then
    echo "Selecting only available one: ${array[1]}" >&2
    # zsh starts at index 1
    echo ${array[1]}
    return
  fi

  printf "%s\n" "${array[@]}" >&2
  while true; do
    read "entry?Enter selection from list above: "
    # checks if the entered entry is in the available ones
    if [[ " ${array[@]} " =~ " ${entry} " ]]; then
      echo $entry
      break
    fi
    echo "Selected entry: '$entry' is not in list" >&2
  done
}

get_network_adapter() {
  local IFS=$'\n'
  available_adapters=()
  # need field 2 because of leading control characters
  for adapter in $(iwctl device list | grep "station\s*$" | awk '{print $2}'); do
    available_adapters+=$adapter
  done
  unset IFS
  select_entry_from_array ${available_adapters[@]}
}

get_online() {
  # checks two sites to see if already online
  if ping -c 1 -q archlinux.org &>/dev/null && ping -c 1 -q example.org &>/dev/null; then
    return
  fi
  adapter=$(get_network_adapter)
  iwctl station $adapter scan
  while true; do
    iwctl station $adapter get-networks
    read "network?Enter network name to connect to: "
    iwctl station $adapter connect $network && break
  done
}

nuke() {
  local device=$(select_device)
  unmount_all
  for partition in $(lsblk --noheadings --paths --output NAME --raw $device); do
    if [ $partition == $device ]; then
      continue
    fi
    if cryptsetup isLuks $partition; then
      echo "Removing luks partition"
      cryptsetup erase $partition
    fi
    echo "Wiping filesystem from $partition"
    wipefs --all $partition
  done
  echo "Removing partition table"
  sgdisk --zap-all $device
}

unmount_all() {
  if findmnt "$SYSROOT" &>/dev/null; then
    echo "Unmounting $SYSROOT"
    umount --all-targets --recursive "$SYSROOT"
  fi
  if findmnt "$SYSROOT/boot" &>/dev/null; then
    echo "Unmounting $SYSROOT/boot"
    umount --all-targets --recursive "$SYSROOT/boot"
  fi
  if [ -e "/dev/mapper/$MAPPER_NAME" ]; then
    echo "Closing decrypted device..." >&2
    cryptsetup close "$MAPPER_NAME" >&2
  fi
}

select_device() {
  local available_devices n_devices device
  # because two columns are selected there may be a trailing tab character
  # even if FSTYPE is empty -> awk first field

  # I think the way to collect output in zsh is terrible
  # https://unix.stackexchange.com/questions/710366/is-there-a-zsh-equivalent-of-bash-builtin-readarray
  local IFS=$'\n' # so every line gets an array field, even if it contains whitespace
  local available_devices=()
  for device in $(lsblk --noheadings --nodeps --paths --output NAME,FSTYPE | grep --perl-regexp '/dev/(sd|nvme|vd)' | grep --invert-match 'iso9660' | awk '{print $1}'); do
    available_devices+=$device
  done
  unset IFS
  select_entry_from_array ${available_devices[@]}
}

is_partition_of_guid() {
  local device=$1
  local partition=$2
  local guid=$3
  sgdisk --info=$partition $device | grep --quiet $guid
}

is_efi_partition() {
  is_partition_of_guid "$1" $2 "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
}

is_linux_fs_partition() {
  # UUID version of typecode 8304
  is_partition_of_guid "$1" $2 "4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709"
}

get_partition_number() {
  local partition_label=$1
  findfs PARTLABEL="$partition_label" | grep --only-matching --perl-regexp "\d+$"
}

count_partitions() {
  local device="${1##*/}"
  grep --count --perl-regexp "${device}p?[0-9]" /proc/partitions
}

microcode() {
  local microcode
  # determines microcode package
  cpu_vendor=$(grep vendor_id /proc/cpuinfo | sort | uniq | awk '{print $3}')
  if [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
    echo amd-ucode
  elif [[ "$cpu_vendor" == "GenuineIntel" ]]; then
    echo intel-ucode
  fi
}

install_base() {
  local country=$(curl --silent 'http://ip-api.com/line?fields=country')

  # updates mirror list before installation, mirror list is copied to /mnt by pacstrap
  local filename="/etc/pacman.d/mirrorlist"
  # runs reflector only if mirrorlist was not updated in the last 24 hours
  # find does return 0 even when nothing is found, so [[ ]] around it
  if [[ $(find "$filename" -mtime +1 -print) ]]; then
    reflector --save $filename --protocol https --country "$country" --latest 10 --sort rate
  fi

  # forces keyring update in host, so we don't run into
  # problems when installing into the new root
  pacman -Sy --noconfirm --needed archlinux-keyring

  # installs base packages
  # -K initializes empty key ring in target
  # efibootmgr used to clean up boot managers in uefi
  # we can just forward additional pacman parameters after the target directory
  packages=(
    base       #
    base-devel # to build aur repo packages
    # linux          # installed after configuring pacman hooks
    linux-firmware #
    mkinitcpio     # initrd generator
    plymouth       # boot splash and unlock screen
    efibootmgr     # to check installed boot managers
    zsh            # the default shell
    vim            # editor
    networkmanager # service to get online
    cryptsetup     # decryption of drives
    btrfs-progs    # btrfs file system utilities
    reflector      # mirrorlist updates
    git            # needed to setup kernel install hooks
    $(microcode)   # determines needed microcode
  )
  pacstrap -K "$SYSROOT" --needed ${packages[@]}

  # configures reflector service. defaults apart from country are ok
  sed -i "s/#?\s*--country.*$/--country $country/" "$SYSROOT/etc/xdg/reflector/reflector.conf"

  # makes vim the default editor
  ln -sf vim "$SYSROOT/usr/bin/vi"
}

reinstall_kernel() {
  # kernel is installed separately, because we want to generate the initrd only once
  arch-chroot "$SYSROOT" pacman -S --noconfirm linux linux-lts
}

remove_all_existing_users_with_home() {
  local userhome user
  # trailing (N) forces nullglob, so no output if no file matches, otherwise it
  # would return the glob pattern
  for userhome in $SYSROOT/home/*(N); do
    rm -r $userhome
    user=$(basename $userhome)
    userdel --root "$SYSROOT" --force "$user"
  done
}

create_user() {
  # root password is disabled by default in arch, but just to be sure, we lock it
  # again
  remove_all_existing_users_with_home
  read "username?Enter username: "
  useradd --root "$SYSROOT" --create-home --groups wheel --shell $(which zsh) "$username"
  arch-chroot "$SYSROOT" passwd "$username"

  # enables autologin for that user
  groupadd --force --root "$SYSROOT" --system autologin
  gpasswd --root "$SYSROOT" --add "$username" autologin
}

clean_bootloaders() {
  for entry in $(efibootmgr |
    grep --fixed-strings "Linux Boot Manager" |
    awk '{print $1}' |
    sed 's/^Boot//;s/\*$//' |
    grep --only-matching --perl-regexp "\d+"); do
    efibootmgr --quiet --bootnum $entry --delete-bootnum
  done
}

setup_bootloader() {
  # installs systemd-boot bootloader. cleans up previously installed linux
  # bootloaders in case we're redoing stuff
  clean_bootloaders
  bootctl --root "$SYSROOT" install
  # configures the bootloader, must not include options, because that overrides the cmdline in the uki
  loader_options=(
    "default *lts*"
    "timeout 1"
    "console-mode auto"
    "editor no"
  )
  printf "%s\n" "${loader_options[@]}" >"$SYSROOT/boot/loader/loader.conf"
}

create_hosts_file() {
  TAB="$(printf '\t')"
  local hostname=$(cat "$SYSROOT/etc/hostname")
  cat >"$SYSROOT/etc/hosts" <<EOF
127.0.0.1${TAB}localhost
::1${TAB}${TAB}localhost
127.0.0.1${TAB}${hostname}
EOF
}

make_wheel_members_sudoers() {
  sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^#\s*//' "$SYSROOT/etc/sudoers"
}

install_aur() {
  local url=$1
  temp_dir=$(mktemp --directory)
  chmod a+rwx $temp_dir
  pacman --sync --noconfirm --needed git fakeroot
  git clone $url $temp_dir
  pushd $temp_dir
  sudo -u nobody makepkg .
  cp *.pkg.tar.zst "$SYSROOT"
  arch-chroot "$SYSROOT" pacman --upgrade --noconfirm *.pkg.tar.zst
  rm $SYSROOT/*.pkg.tar.zst
  popd
  # rm -r $temp_dir
}

setup_initrd_generator() {
  # https://wiki.archlinux.org/title/Unified_kernel_image#kernel-install

  # configures unified kernel image format
  echo "layout=uki" >"$SYSROOT/etc/kernel/install.conf"
  # fix for https://gitlab.archlinux.org/archlinux/packaging/packages/systemd/-/issues/19
  echo "uki_generator=mkinitcpio" >>"$SYSROOT/etc/kernel/install.conf"

  # need to deactivate the pacman hooks for mkinitcpio, because it shall call kernel-install instead
  ln -sf /dev/null "$SYSROOT/usr/share/libalpm/hooks/60-mkinitcpio-remove.hook"
  ln -sf /dev/null "$SYSROOT/usr/share/libalpm/hooks/90-mkinitcpio-install.hook"

  # installs the pacman hook that uses kernel-install
  install_aur https://aur.archlinux.org/pacman-hook-kernel-install.git

  # sets up necessary hooks for decryption
  sed -i "s|^HOOKS.*|HOOKS=( ${mkinitcpio_hooks[*]} )|" "$SYSROOT/etc/mkinitcpio.conf"

  # we use the crypttab file instead of the rd.luks.name kernel parameter, because we can use the
  # gpt part label there instead of the uuid of the encrypted partition. WE MUST ONLY USE EITHER THE
  # crypttab OR THE KERNEL PARAMETER!
  # the .initramfs extension automatically adds it to the initrd, see
  # https://wiki.archlinux.org/title/dm-crypt/System_configuration#Using_systemd-cryptsetup-generator

  # the sd-encrypt runs systemd-cryptsetup-generator, that takes a /etc/crypttab.initramfs
  # and puts it as /etc/crypttab into the initrd
  echo "$MAPPER_NAME PARTLABEL=$ROOT_LABEL none luks" >"$SYSROOT/etc/crypttab.initramfs"

  # kernel-install uses this file
  echo "${kernel_cmdline[*]}" >"$SYSROOT/etc/kernel/cmdline"
}

install_nvidia_driver() {
  echo "Found NVIDIA card, installing driver" >&2
  packages=(
    linux-headers   # needed to build the nvidia kernel module
    dkms            # framework for building kernel modules
    nvidia          # the driver package
    nvidia-settings # settings gui
    libva-utils     # support for hardware acceleration via VDPAU and NVDEC/NVENC (depending on model)
  )
  # hardware acceleration translation layers:
  # libva-vdpau-driver   # translation layer that offers VA-API and utilizes the VDPAU backend (old, not used)
  # libvdpau-va-gl       # translation layer that offers VDPAU and utilizes the VAAPI backend (not needed for proprietary driver)
  # nvidia-vaapi-driver  # translation layer that offers VA-API and utilizes the NVDEC backend (designed for firefox, decoding only, see https://github.com/elFarto/nvidia-vaapi-driver)

  # nvidia package blacklists nouveau by itself, so we don't need to
  arch-chroot "$SYSROOT" pacman -S --noconfirm --needed ${packages[@]}
  install_aur https://aur.archlinux.org/libva-nvidia-driver.git # hardware acceleration (see above)

  # removes kms (kernel mode setting) hook from mkinitcpio
  mkinitcpio_hooks=("${mkinitcpio_hooks[@]/kms/}")

  # enables DRM (Direct Rendering Manager) kernel mode setting, both _ and - work in the module name, see
  # https://github.com/elFarto/nvidia-vaapi-driver/issues/198
  kernel_cmdline+=(
    nvidia_drm.modeset=1
  )

  environment_entries=(
    NVD_BACKEND=direct # needed until https://github.com/elFarto/nvidia-vaapi-driver/issues/126 is resolved
  )

  # adds driver modules mkinitcpio so they are available in the initrd and
  # loaded at the earliest possible stage during boot ( i915 is for intel graphics )
  mkinitcpio_modules+=(
    i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm
  )

  # since kernel-install is set up to generate the initrd, the hook from
  # https://aur.archlinux.org/nvidia-initramfs-pacman-hook.git and
  # https://wiki.archlinux.org/title/NVIDIA#pacman_hook can't be used
  # instead we use a custom hook that calls kernel-install
  # but we do this AFTER installing, so it's called the first time
  # when the kernel is installed

  cat >"${SYSROOT}/usr/share/libalpm/hooks/80-nvidia-update.hook" <<EOF
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia
Target=linux

[Action]
Description=Update NVIDIA module in initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/usr/share/libalpm/scripts/nvidia-install
EOF

  cat >"${SYSROOT}/usr/share/libalpm/scripts/nvidia-install" <<EOF
#! /bin/sh
# checks if the kernel is updated in this pacman run as well, if so, do not
# run kernel-install, because the kernel updates triggers it
while read -r target; do
  case \$target in linux)
    exit 0
    ;;
  esac
done
/usr/share/libalpm/scripts/kernel-install add
EOF
  chmod u+x "${SYSROOT}/usr/share/libalpm/scripts/nvidia-install"
}

install_amd_driver() {
  echo "Found AMD card, installing packages" >&2
  packages=(
    mesa
    libva-mesa-driver # hardware video acceleration for VA-API
    mesa-vdpau        # hardware video acceleration for VDPAU api
  )
  arch-chroot "$SYSROOT" pacman -S --noconfirm --needed ${packages[@]}
}

install_graphics_driver() {
  echo "Looking for NVIDIA card..." >&2
  # checks for nvidia graphics card and installs proprietary driver
  # adds driver to initrd for early loading
  # disables nouveau driver, adds drivers for video encoding / decoding on hardware
  lspci -k 2>/dev/null | grep --after-context 2 --extended-regexp "(VGA|3D)" | grep --quiet --ignore-case nvidia && install_nvidia_driver

  echo "Looking for AMD card..." >&2
  lspci -k 2>/dev/null | grep --after-context 2 --extended-regexp "(VGA|3D)" | grep --quiet "AMD\|ATI\|Radeon" && install_amd_driver

  echo "Looking for Intel card..." >&2
  lspci -k 2>/dev/null | grep --after-context 2 --extended-regexp "(VGA|3D)" | grep --quiet "AMD\|ATI\|Radeon" && arch-chroot "$SYSROOT" pacman -S --noconfirm --needed intel-media-driver
}

main() {
  get_online
  device=$(select_device)

  serial=$(udevadm info --query=property --property=ID_SERIAL_SHORT --value --name=$device)
  BOOT_LABEL="${BOOT_LABEL_PREFIX}_${serial}"
  ROOT_LABEL="${ROOT_LABEL_PREFIX}_${serial}"
  MAPPER_NAME="${MAPPER_NAME_PREFIX}_${serial}"

  unmount_all

  if $FORCE ||
    [ $(count_partitions $device) != "2" ] ||
    ! is_efi_partition $device $(get_partition_number $BOOT_LABEL) ||
    ! is_linux_fs_partition $device $(get_partition_number $ROOT_LABEL); then
    echo "Creating partition table"
    # ef00 : EFI system partition
    # 8304 : Linux x86-64 root (/), systemd can automatically mount that (gpt-auto-root)
    sgdisk --zap-all \
      --new=1:0:+512M --typecode=1:ef00 \
      --change-name="1:$BOOT_LABEL" \
      --new=2:0:0 --typecode=2:8304 \
      --change-name="2:$ROOT_LABEL" \
      $device
  else
    echo "Skipping partitioning, already satisfied."
  fi

  # tells OS that the partition table changed
  sleep 1
  partprobe $device
  sleep 1

  boot_partition=$(realpath /dev/disk/by-partlabel/$BOOT_LABEL)
  root_partition=$(realpath /dev/disk/by-partlabel/$ROOT_LABEL)

  # Enable discards and disable workqueues, see
  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)
  # and
  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Disable_workqueue_for_increased_solid_state_drive_(SSD)_performance
  cryptopts=(
    --allow-discards
    --perf-no_read_workqueue
    --perf-no_write_workqueue
    --persistent
  )
  # checks if root partition already is luks encrypted
  # and encrypts it, if not
  if $ENCRYPT; then
    if $FORCE || ! cryptsetup isLuks $root_partition; then
      echo "Encrypting root partition"
      while true; do
        # r : read raw input (including \)
        # s : do not show typed characters
        read -rs "passphrase?Enter encryption passphrase: "
        echo "" >&2
        read -rs "confirmation?Confirm passphrase: "
        echo "" >&2
        if [ "$passphrase" != "$confirmation" ]; then
          echo "Passphrases do not match!" >&2
        else
          break
        fi
      done
      # encrypts root device and opens it
      echo "$passphrase" | cryptsetup luksFormat --type luks2 --label "$MAPPER_NAME" "$root_partition" >&2
      echo "$passphrase" | cryptsetup luksOpen ${cryptopts[*]} "$root_partition" "$MAPPER_NAME" >&2
    else
      echo "Opening encrypted root partition"
      cryptsetup open ${cryptopts[*]} "$root_partition" "$MAPPER_NAME"
    fi
    root_partition="/dev/mapper/${MAPPER_NAME}"
    # root_uuid=$(blkid --output value --match-tag UUID $root_partition)
    # kernel_cmdline+="rd.luks.name=${root_uuid}=${MAPPER_NAME}"
  fi
  # defines the root device to be mounted
  kernel_cmdline+="root=$root_partition"

  if $FORCE || [ "$(blkid --output value --match-tag TYPE $boot_partition)" != "vfat" ]; then
    echo "Formatting $boot_partition as fat32"
    mkfs.fat -F 32 -n "${BOOT_LABEL:0:11}" "$boot_partition"
  else
    echo "$boot_partition is already formatted as vfat"
  fi

  # blkid exits with nonzero if there is no file system
  if $FORCE || [ "$(blkid --output value --match-tag TYPE $root_partition)" != "btrfs" ]; then
    echo "Formatting $root_partition as btrfs"
    mkfs.btrfs --force --label "$ROOT_LABEL" "$root_partition"
  else
    echo "$root_partition is already formatted as btrfs"
  fi

  # creates subvolumes, explicitly define / as subvolme so the the default
  # subvolume is not mounted
  mount --options "$mount_options,subvol=/" "$root_partition" "$SYSROOT"

  # removes subvolumes that are not requested but exist
  # existing_subvolumes=$(btrfs subvolume list -t $SYSROOT | sed 1,2d | awk '{print $4}')
  # to_delete=$(echo ${subvolumes[@]} ${existing_subvolumes[@]} | tr ' ' '\n' | sort | uniq --unique)
  # if [[ -n $to_delete ]]; then
  #   # no double quotes, because we want whitespace to separate the subvolme names
  #   echo "deleting unwanted subvolumes"
  #   echo "$to_delete"
  #   btrfs subvolume delete $to_delete
  # fi

  for subvol in ${subvolumes[@]}; do
    # &> redirects stdout and stderr
    if ! btrfs subvolume show "$SYSROOT/$subvol" &>/dev/null; then
      btrfs subvolume create "$SYSROOT/$subvol"
    fi
  done
  # the first entry is used as default subvolume, to that
  # gpt-auto-root mounts the correct root
  btrfs subvolume set-default "$SYSROOT/${subvolumes[1]}"

  umount --all-targets --quiet --recursive "$root_partition"

  # mounts the default subvolume as root
  mount --options "${mount_options}" "$root_partition" "$SYSROOT"
  for subvol in ${subvolumes[@]}; do
    if [ $subvol = "@" ]; then
      continue
    fi
    mount_point="${subvol}"
    mount_point="${mount_point:1}"        # drops leading @
    mount_point="${mount_point//_//}"     # replaces _ with /
    mount_point="$SYSROOT/${mount_point}" # prepends /mnt
    echo "mounting $subvol to $mount_point"
    mount --mkdir --options "${mount_options},subvol=$subvol" "$root_partition" "$mount_point"
  done

  # mounts boot (must be after root!)
  mount --mkdir $boot_partition "$SYSROOT/boot"

  install_base
  install_graphics_driver

  # the one from the arch iso (comments only) is used as a template
  cp /etc/fstab "$SYSROOT/etc/fstab"
  genfstab -t PARTLABEL "$SYSROOT" >>"$SYSROOT/etc/fstab"
  # genfstab includes subvolume id and subvolume name, but we only want the name in there
  # to be able to switch root to a backup, we also need the / mount point to not have any
  # subvolume specified at all
  sed -i -e 's/subvolid=[0-9]\+,\?//' -e 's|,\?subvol=/@\(\s\)|\1|' "$SYSROOT/etc/fstab"

  if [ -f "${SYSROOT}/etc/hostname" ]; then
    hostname=$(head -n 1 "${SYSROOT}/etc/hostname")
  else
    read "hostname?Enter Hostname: "
  fi

  systemd-firstboot \
    --root "$SYSROOT" \
    --locale=en_US.UTF-8 \
    --locale-messages=en_US.UTF-8 \
    --keymap=us \
    --timezone=$(curl --silent 'http://ip-api.com/line?fields=timezone') \
    --hostname=$hostname \
    --root-shell="$(which zsh)" \
    --setup-machine-id \
    --force \
    --delete-root-password \
    --welcome=no

  sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' "${SYSROOT}/etc/locale.gen"
  arch-chroot ${SYSROOT} locale-gen

  create_hosts_file

  # the btrfs subvolme layout is flat, so child subvolumes are not automatically
  # mounted by gpt-auto-root and we need a fstab, which will include a redundant entry,
  # but thanks to gpt-auto-root we don't need to tell the kernel where the root dir is

  setup_initrd_generator
  reinstall_kernel # forces pacman hook to regerate initrds

  setup_bootloader
  create_user
  make_wheel_members_sudoers

  systemctl --root "${SYSROOT}" enable "${services[@]}"
}

if [[ ! $ZSH_EVAL_CONTEXT =~ ':file$' ]]; then
  # -e : Exit immediately if a command exits with a non-zero status.
  # -u : Treat unset variables as an error when substituting.
  # -f : Disable file name generation (globbing).
  # -o pipefail : the return value of a pipeline is the status of the last command
  #               to exit with a non-zero status, or zero if no command exited
  #               with a non-zero status
  set -euf -o pipefail

  cmd_options=$(getopt --options fn --longoptions force,no-encryption --name 'install-arch' -- "$@")

  if [ $? != 0 ]; then
    # failed to parse input arguments
    echo "Problem..." >&2
    # exit 1
  fi

  # getopt above reordered inputs, this resets then to the input parameters
  # so they can be parsed below
  eval set -- "$cmd_options"

  while true; do
    case "$1" in
    -f | --force)
      FORCE=true
      shift
      ;;
    -n | --no-encryption)
      ENCRYPT=false
      shift
      ;;
    --)
      shift
      break
      ;;
    *) break ;;
    esac
  done

  main
fi
