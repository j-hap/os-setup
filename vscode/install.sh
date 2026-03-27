#! /bin/bash

# debian
if command -v apt >/dev/null 2>&1; then
  echo "apt"
  exit 1
fi

# fedora
if command -v dnf &>/dev/null; then
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<EOF
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc"
EOF
  sudo dnf check-update
  sudo dnf --assumeyes install code
fi

# arch
if command -v paru &>/dev/null; then
  paru -S visual-studio-code-bin
elif command -v pacman &>/dev/null; then
  git clone https://aur.archlinux.org/visual-studio-code-bin.git $HOME/aur/vscode
  pushd $HOME/aur/vscode >/dev/null
  makepkg --syncdeps --install --noconfirm
  popd
fi

extensions=(
  adpyke.codesnap
  alefragnani.Bookmarks
  charliermarsh.ruff # pulls in all necessary python extensions
  dqisme.sync-scroll
  daohong-emilio.yash
  dracula-theme.theme-dracula
  foxundermoon.shell-format
  frenya.vscode-recall
  James-Yu.latex-workshop
  ms-vscode.cmake-tools
  ms-vscode.cpptools
  ms-vscode.cpptools-extension-pack
  ms-vscode.cpptools-themes
  ms-vscode.hexeditor
  njpwerner.autodocstring
  redhat.vscode-xml
  rust-lang.rust-analyzer
  stkb.rewrap
  tamasfe.even-better-toml
  vadimcn.vscode-lldb
  yzhang.markdown-all-in-one
)

command="code"
for extension in ${extensions[@]}; do
  command+=" --install-extension $extension"
done
eval "$command"

here=$(dirname -- "$(readlink --canonicalize -- "$0")")
cp "$here/settings.json" ~/.config/Code/User/settings.json
cp "$here/keybindings.json" ~/.config/Code/User/keybindings.json
