#! /bin/bash

if command -v ptyxis 2>&1 >/dev/null; then
  exit 1
fi

gsettings set org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/${PTYXIS_PROFILE}/ palette 'dracula'
