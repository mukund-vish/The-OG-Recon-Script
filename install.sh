#! /bin/bash

script="og-recon.sh"
install_path="/usr/local/bin/og-recon"

echo "Checking and Installing Dependencies.........."
apt install nmap
apt install amass -y
apt install golang -y
apt install python3 -y
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
git clone https://github.com/devanshbatham/paramspider
go install github.com/tomnomnom/httprobe@latest

echo "Installing og-recon...."
cp "$script" "$install_path"

chmod +x $install_path

if [[ -f "$install_path" && -x "$install_path" ]]; then
	echo "Installation Complete! You can use it now : og-recon domain.com"
else
	echo "Installation Falied. Please check your permission"
	exit 1
fi
