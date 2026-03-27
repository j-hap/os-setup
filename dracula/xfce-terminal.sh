apply_theme() {
  local theme="$1"
  local IFS=$'\n'
  for setting in $(cat "$theme" | grep '='); do
    local key=$(echo $setting | cut -d '=' -f 1)
    sed -i "s/^$key=.*$/$setting/" ~/.config/xfce4/terminal/terminalrc
  done
  unset IFS
}

if ! command -v xfce-terminal 2>&1 >/dev/null; then
  echo "xfce-terminal could not be found"
  exit 1
fi

mkdir --parents $HOME/dracula
pushd $HOME/dracula >/dev/null
if [ ! -d "xfce4-terminal" ]; then
  git clone --quiet https://github.com/dracula/xfce4-terminal.git
else
  pushd "xfce4-terminal" >/dev/null
  git reset --hard --quiet
  git clean -d --force --quiet
  git pull --quiet
  popd >/dev/null
fi
mkdir --parents $HOME/.local/share/xfce4/terminal/colorschemes
ln -sf $(realpath xfce4-terminal/Dracula.theme) $HOME/.local/share/xfce4/terminal/colorschemes/.
# either go to Edit -> Preferences -> Colors -> Presets -> Load Presets...
# or run the function
apply_theme "$HOME/.local/share/xfce4/terminal/colorschemes/Dracula.theme"
popd >/dev/null
