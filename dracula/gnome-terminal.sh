#! /bin/bash

if command -v gnome-terminal 2>&1 >/dev/null; then
  exit 1
fi

target_dir="$HOME/dracula/gnome-terminal"
mkdir --parents $target_dir
git clone --quiet https://github.com/dracula/gnome-terminal $target_dir
pushd $target_dir &>/dev/null
profile=$(gsettings get org.gnome.Terminal.ProfilesList default)
# need to drop first and last character because gsettings returns the uuid in single quotes
profile=${profile:1:-1}
./install.sh --scheme Dracula --profile ":$profile" --skip-dircolors
popd &>/dev/null
