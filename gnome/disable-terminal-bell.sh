gsettings set org.gnome.desktop.wm.preferences audible-bell false
gsettings set org.gnome.desktop.wm.preferences visual-bell false

gsettings set org.gnome.Ptyxis audible-bell false
gsettings set org.gnome.Ptyxis visual-bell false

gsettings set org.gnome.terminal.legacy.profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9 audible-bell false

sudo sed -i "s/#set bell-style none/set bell-style none/" /etc/inputrc
