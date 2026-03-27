#!/bin/zsh

SYSROOT="/mnt"

packages=(
  # desktop environment
  xfce4                    # desktop environment bundle
  lightdm                  # display manager
  lightdm-gtk-greeter      # login page
  light-locker             # lock screen
  xfce4-screenshooter      # screenshot util
  xfce4-whiskermenu-plugin # alternative application menu
  xfce4-pulseaudio-plugin  # adjust volume from xfce panel
  network-manager-applet   # network management in panel
  gvfs                     # for automatic management of removable devices

  # development
  man-db     # man pages
  noto-fonts # google tt fonts
  git        # version control
  gdb        # debugger
  clang      # at least for clang-format

  # communication
  discord        # (video)chatting
  signal-desktop # encrypted instant messenger

  # utils
  usbutils          # usb device info
  wget              # command line file download
  neofetch          # flexing
  rsync             # sync util
  keepassxc         # password manager
  vlc               # video player
  libreoffice-still # office applications
  ristretto         # image viewer
  galculator        # graphical calculator

  # audio
  pipewire       # Low-latency audio/video router and processor
  pipewire-alsa  # Low-latency audio/video router and processor - ALSA configuration
  pipewire-jack  # Low-latency audio/video router and processor - JACK support
  pipewire-audio # Low-latency audio/video router and processor - Audio support (including bluetooth)
  pipewire-pulse # Low-latency audio/video router and processor - PulseAudio replacement
  wireplumber    # Session / policy manager implementation for PipeWire
  pavucontrol    # audio mixer

  # bluetooth
  bluez       #
  bluez-utils #
  blueman     # for graphics management

  # browser
  firefox
  # mail
  thunderbird
)

# should be added to autostart automatically
# blueman-applet
# nm-applet

services=(
  # Desktop services
  lightdm.service   # Desktop manager
  bluetooth.service # bluetooth
)

user_services=(
  # Audio
  pipewire.service
  pipewire-pulse.service
  wireplumber.service
)

diable_pc_speaker() {
  cat >"${SYSROOT}/etc/modprobe.d/nobeep.conf" <<EOF
blacklist pcspkr
blacklist snd_pcsp
EOF

  sed -i 's/#set bell-style none/set bell-style none/' "${SYSROOT}/etc/inputrc"
}

automount_as_ntfs3() {
  # creates a rule so that auto mounted devices are mounted as ntfs3 instead of ntfs-3g (fuseblk)
  cat >/etc/udev/rules.d/90-ntfs3-automount.rules <<EOF
SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="ntfs", ENV{ID_FS_TYPE}="ntfs3" , ENV{UDISKS_FILESYSTEM_SHARED}="0"
EOF
}

hardware_decoding_support() {
  pacman --query --quiet libva-nvidia-driver &>/dev/null
  has_vaapi_driver=$?
  pacman --query --quiet firefox &>/dev/null
  has_firefox=$?
  if [ $has_vaapi_driver ] && [ $has_firefox ]; then
    # firefox and libva-nvidia-driver installed
    for user in $(cat /etc/passwd | grep home | cut -d ":" -f 1); do
      # adds the necessary configs to each users preferences
      if [ ! -f "${SYSROOT}/home/$user/.mozilla/firefox/profiles.ini" ]; then
        arch-chroot "${SYSROOT}" su - $user -c "firefox -CreateProfile default-release"
      fi
      for profile in $(grep 'Path=' "${SYSROOT}/home/$user/.mozilla/firefox/profiles.ini" | cut -d "=" -f 2); do
        preffile="${SYSROOT}/home/$user/.mozilla/firefox/${profile}/user.js"
        if [ -f "${preffile}" ]; then
          sed -i '/user_pref("media.ffmpeg.vaapi.enabled"/d' "${preffile}"
          sed -i '/user_pref("media.rdd-ffmpeg.enabled"/d' "${preffile}"
          sed -i '/user_pref("media.av1.enabled"/d' "${preffile}"           # only very new nvidia cards support this
          sed -i '/user_pref("widget.dmabuf.force-enabled"/d' "${preffile}" # nvidia driver >500
        fi
        cat >>"${preffile}" <<EOF
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.rdd-ffmpeg.enabled", true);
user_pref("media.av1.enabled", false);
user_pref("widget.dmabuf.force-enabled", true);
EOF
      done
    done
  fi
  cat >"${SYSROOT}/etc/environment" <<EOF
MOZ_DISABLE_RDD_SANDBOX=1
EGL_PLATFORM=$XDG_SESSION_TYPE
LIBVA_DRIVER_NAME=nvidia
EOF
}

main() {
  echo "Installing packages..." >&2
  arch-chroot "${SYSROOT}" pacman -Syu --needed --noconfirm "${packages[@]}"
  echo "Enabling services..." >&2
  systemctl --root "$SYSROOT" enable "${services[@]}"
  echo "Enabling user services..." >&2
  # user services are enable as every user there is
  IFS=$'\n'
  for user in $(cat /etc/passwd | grep home | cut -d ":" -f 1); do
    echo "Enabling user services for $user" >&2
    arch-chroot "${SYSROOT}" su - $user -c "systemctl --user enable ${user_services[@]}"
  done
  unset IFS
  diable_pc_speaker
  automount_as_ntfs3
  hardware_decoding_support
}

if [[ ! $ZSH_EVAL_CONTEXT =~ ':file$' ]]; then
  # -e : Exit immediately if a command exits with a non-zero status.
  # -u : Treat unset variables as an error when substituting.
  # -o pipefail : the return value of a pipeline is the status of the last command
  #               to exit with a non-zero status, or zero if no command exited
  #               with a non-zero status
  set -eu -o pipefail
  main
fi
