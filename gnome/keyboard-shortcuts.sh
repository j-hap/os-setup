#! /bin/bash

gsettings set org.gnome.settings-daemon.plugins.media-keys home ["'<Super>e'"]
gsettings set org.gnome.desktop.wm.keybindings show-desktop ["'<Super>d'"]

gsettings set org.gnome.shell.keybindings show-screenshot-ui ["'<Shift><Super>s'"]

if command -v ptyxis &>/dev/null; then
  command='ptyxis --new-window'
else
  command='gnome-terminal --window'
fi

gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings ["'/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/'"]
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Control><Alt>t'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command "${command}"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'New Terminal'

