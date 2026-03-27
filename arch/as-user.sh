#! /bin/zsh

oh_my_zsh() {
  if [ -e $HOME/.oh-my-zsh ]; then
    omz update
    return
  fi
  sh -c "$(curl --fail --silent --show-error --location https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  sed -i 's/^ZSH_THEME=.*$/ZSH_THEME=murilasso/' $HOME/.zshrc
}

get_plugin_id() {
  local plugin_name=$1
  xfconf-query --channel xfce4-panel --property /plugins --list --verbose | grep plugin_name | awk '{print $1}' | grep --only-matching --perl-regexp "\d$"
}

action_menu_items() {
  # finds the actions plugin
  actions_plugin=$(xfconf-query --channel xfce4-panel --property /plugins --list --verbose | grep action | awk '{print $1}')
  # to disable / enable certain entries in the actions plugin, change the leading character,
  # + : enabled
  # - : disabled
  xfconf-query --channel xfce4-panel --property "${actions_plugin}/items" \
    --type 'string' --set "+lock-screen" \
    --type 'string' --set "-switch-user" \
    --type 'string' --set "+separator" \
    --type 'string' --set "+suspend" \
    --type 'string' --set "-hibernate" \
    --type 'string' --set "-hybrid-sleep" \
    --type 'string' --set "-separator" \
    --type 'string' --set "+shutdown" \
    --type 'string' --set "+restart" \
    --type 'string' --set "-separator" \
    --type 'string' --set "-logout" \
    --type 'string' --set "-logout-dialog"
}

disable_workspace_switcher() {
  # removes workspace switcher from panel
  # finds the workspace switcher (pager)
  plugin=$(xfconf-query --channel xfce4-panel --list --verbose | grep pager | awk '{print $1}')
  if [ ! -z "$plugin" ]; then
    plugin_id=$(echo "$plugin" | grep -o '[0-9]*$')
    for panel_id in $(xfconf-query --channel xfce4-panel --property /panels | sed '1,2d'); do
      echo "Removing $plugin from panel $panel_id"
      shown_plugins=$(xfconf-query --channel xfce4-panel --property /panels/panel-${panel_id}/plugin-ids | sed '1,2d')
      filtered_plugins=$(echo $shown_plugins | sed "s/$plugin_id//g")
      set_command=$(echo $filtered_plugins | sed 's/\([0-9]\+\)/--type int --set \1/g')
      xfconf-query --channel xfce4-panel --property /panels/panel-${panel_id}/plugin-ids --force-array $set_command
    done
  fi
}

app_searcher_with_super_l() {
  # starts application searcher when pressing Super_L
  xfconf-query --channel xfce4-keyboard-shortcuts --property /commands/custom/Super_L --create --type string --set "xfce4-appfinder"
}

install_vcpkg() {
  install_dir="$HOME/.vcpkg"
  if [ -d ${install_dir}/.git ]; then
    pushd ${install_dir} >/dev/null
    git pull
  else
    git clone https://github.com/Microsoft/vcpkg.git ${install_dir}
    pushd ${install_dir} >/dev/null
  fi
  ./bootstrap-vcpkg.sh -disableMetrics
  popd >/dev/null
  cat >${install_dir}/env <<EOF
#!/bin/sh
# vcpkg shell setup
# affix colons on either side of \$PATH to simplify matching
case ":\${PATH}:" in
    *:"\$HOME/.vcpkg":*)
        ;;
    *)
        export PATH="\$PATH:\$HOME/.vcpkg"
        ;;
esac
EOF
  line='. "$HOME/.vcpkg/env"'
  for f in $HOME/.bash_profile $HOME/.profile $HOME/.zshenv $HOME/.bashrc; do
    sed -i "\|$line|d" $f
    echo $line >>$f
  done
}

integrate_cargo() {
  cat >$HOME/.cargo/env <<EOF
#!/bin/sh
# cargo binaries shell setup
# affix colons on either side of \$PATH to simplify matching
case ":\${PATH}:" in
    *:"\$HOME/.cargo":*)
        ;;
    *)
        export PATH="\$PATH:\$HOME/.cargo/bin"
        ;;
esac
EOF
  line='. "$HOME/.cargo/env"'
  for f in $HOME/.bash_profile $HOME/.profile $HOME/.zshenv $HOME/.bashrc; do
    sed -i "\|$line|d" $f
    echo $line >>$f
  done
}

main() {
  desktop_environment=$(echo $XDG_CURRENT_DESKTOP | tr '[:upper:]' '[:lower:]')
  here="$(dirname "$(realpath $0)")"
  $here/$desktop_environment/all.sh
  texlive/texlive.sh
  oh_my_zsh
  install_vcpkg
}

if ([ -n "${BASH_SOURCE}" ] && [ "$0" = "${BASH_SOURCE}" ]) || ([ -n "${ZSH_EVAL_CONTEXT}" ] && [[ ! "${ZSH_EVAL_CONTEXT}" =~ ':file$' ]]); then
  main
fi
