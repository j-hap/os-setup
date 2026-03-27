#! /bin/bash
user=$(whoami)
filename="/etc/gdm/custom.conf"

# inserts category header if it is not already present
if ! grep -q "\[daemon\]" $filename 2>/dev/null; then
  echo "[daemon]" | sudo tee -a $filename >/dev/null
fi
# removes any old setting, no matter if it is commented out or not, to prevent duplicates
sudo sed -i "/AutomaticLoginEnable=/d" $filename

sudo sed -i "/AutomaticLogin=/d" $filename

# inserts the config lines just below the section header
sudo sed -i "/\[daemon\]/a AutomaticLoginEnable=True\nAutomaticLogin=${user}" $filename