#!/usr/bin/env bash

set -euo pipefail
export PATH="$PATH:$HOME/go/bin"
export PATH="$PATH:$(go env GOPATH 2>/dev/null)/bin"
if ! grep -q 'go env GOPATH' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> "$HOME/.bashrc"
fi

red="\033[31m"
green="\033[32m"
yellow="\033[33m"
blue="\033[34m"
reset="\033[0m"
if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
    echo -e "${red}Usage: $0 <domain>${reset}"
    echo "Example: $0 example.com"
    exit 1
fi

domain="$1"
dir="$domain"

required_tools=(subfinder httprobe assetfinder paramspider dig whois amass nmap toilet)
missing_tools=()
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        missing_tools+=("$tool")
    fi
done
if [ "${#missing_tools[@]}" -gt 0 ]; then
    echo -e "${red}Missing required tools: ${missing_tools[*]}${reset}"
    echo "Run ./install.sh first."
    exit 1
fi

cleanup() {
    echo -e "\n${yellow}Scan(s) interrupted. Output (if generated) stored in $dir${reset}"
    echo -e "${blue}Thank you for using OG-RECON!${reset}"
    exit 1
}
trap cleanup SIGINT

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p "$pid" &>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep "$delay"
        printf "\b\b\b\b\b\b"
    done
    printf "         \b\b\b"
}

mkdir -p "$dir"

clear
echo -e "${blue}"
toilet -f slant "OG-RECON" --filter border
echo -e "${reset}"
echo -e "${green}"
toilet -f term "Created by Mukund Vishwakarma | Version:1.1"
echo -e "${reset}"
echo -e "${blue}"
toilet -f term "Target:$domain" --filter border
echo -e "${reset}"

echo -e "${red}This script will actively scan $domain and every subdomain it discovers,"
echo -e "including OS fingerprinting and vulnerability scripts via Nmap.${reset}"
read -r -p "Type YES to confirm you are authorized to test this target: " confirm
if [ "$confirm" != "YES" ]; then
    echo -e "${yellow}Aborting - authorization not confirmed.${reset}"
    exit 1
fi

echo -e "${blue}|====================================|${reset}"
echo -e "${green}|======Initializing DOMAIN RECON=====|${reset}"
echo -e "${blue}|====================================|${reset}"

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Finding Sub domain"
echo -e "${red}|--------------------------------------------------|${reset}"

subdomains="$dir/subdomains.txt"
subfinder -d "$domain" -o "$subdomains" -silent &
spinner $!
wait

sort -u "$subdomains" -o "$subdomains" 2>/dev/null
no_subdomains=0
if [ -s "$subdomains" ]; then
    no_subdomains=$(wc -l < "$subdomains")
    echo -e "${yellow}[*]Subdomains Found, stored in $subdomains${reset} Total:${red}$no_subdomains${reset}"
else
    echo -e "${red}[*]No subdomains were found${reset}"
fi

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Finding Sub-Sub domain"
echo -e "${red}|--------------------------------------------------|${reset}"

subsubdomains="$dir/subsubdomains.txt"
if [ -s "$subdomains" ]; then
    subfinder -dL "$subdomains" -o "$subsubdomains" -silent &
    spinner $!
    wait
fi
no_subsubdomains=0
if [ -s "$subsubdomains" ]; then
    no_subsubdomains=$(wc -l < "$subsubdomains")
    echo -e "${yellow}[*]Sub-Sub Domains Found, stored in $subsubdomains Total:$no_subsubdomains${reset}"
else
    echo -e "${red}[*]No Sub-Sub Domains were found${reset}"
fi

echo -e "${yellow}{*}Merging Both files.......${reset}"
data_domain="$dir/datadom.txt"
: > "$data_domain"
[ -s "$subdomains" ] && cat "$subdomains" >> "$data_domain"
[ -s "$subsubdomains" ] && cat "$subsubdomains" >> "$data_domain"
echo -e "${yellow}{*}File Merged into $data_domain${reset}"

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Performing a Recursive scan ....."
echo -e "${red}|--------------------------------------------------|${reset}"

recursive="$dir/recursive.txt"
if [ -s "$data_domain" ]; then
    subfinder -dL "$data_domain" -o "$recursive" -recursive -silent &
    spinner $!
    wait
fi

if [ -s "$recursive" ]; then
    no_recursive=$(wc -l < "$recursive")
    echo -e "${yellow}[*]Subdomains Found, stored in $recursive Total:$no_recursive${reset}"
else
    echo -e "${red}[*]No subdomains were found${reset}"
fi

echo -e "${yellow}{*}Cleaning and Merging ......${reset}"
[ -s "$recursive" ] && cat "$recursive" >> "$data_domain"
if [ "$(wc -l < "$data_domain")" -gt 1 ]; then
    sort -u "$data_domain" -o "$data_domain" &
    spinner $!
    wait
else
    echo -e "${blue}{}File does not require cleaning, skipping it${reset}"
fi
echo -e "${yellow}{*}Cleaning and Merging Finished${reset}"

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Finding Active Subdomains.........."
echo -e "${red}|--------------------------------------------------|${reset}"
active_domain="$dir/active.txt"
if [ -s "$data_domain" ]; then
    httprobe < "$data_domain" > "$active_domain" &
    spinner $!
    wait
fi

real_number=0
if [ -s "$active_domain" ]; then
    real_number=$(sed -E 's#^https?://##' "$active_domain" | sed 's#/$##' | sort -u | wc -l)
    echo -e "${yellow}[*]Active SubDomains, stored in $active_domain Total:$real_number${reset}"
else
    echo -e "${red}{*}No Active subdomains were found${reset}"
fi

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Additional Scan"
echo -e "${red}|--------------------------------------------------|${reset}"

assetfinder "$domain" > "$dir/additional" &
spinner $!
wait

echo -e "${yellow}[*]Additional Scan finished, Results stored in $dir/additional${reset}"

echo -e "${red}|--------------------------------------------------|${reset}"
echo -e "${blue} DOMAIN STATS ${reset}"
echo -e "${green}------>${reset}Total Subdomains:${red}$no_subdomains${reset}"
echo -e "${green}------->${reset}Total Active Subdomains:${red}$real_number${reset}"
echo -e "${red}|--------------------------------------------------|${reset}"
echo "Domain Scan Finished..........."
echo -e "${red}|--------------------------------------------------|${reset}"

echo -e "${blue}|====================================|${reset}"
echo -e "${green}|===Initializing Additional RECON===|${reset}"
echo -e "${blue}|====================================|${reset}"

echo -e "${yellow}[*]Finding Parameters for Domain......${reset}"
paramspider -d "$domain" > /dev/null &
spinner $!
wait
if [ -f "results/$domain.txt" ]; then
    mv "results/$domain.txt" "$dir"
    echo -e "${green}[..]REAL OUTPUT STORED IN $dir/$domain.txt${reset}"
else
    echo -e "${red}[*]Paramspider produced no output file (check your paramspider version/config)${reset}"
fi

echo -e "${yellow}[*]Finding DNS records for domain and Subdomains${reset}"
dns="$dir/dns.txt"
dig @8.8.8.8 "$domain" > "$dns" &
spinner $!
wait
if [ -s "$data_domain" ]; then
    while read -r sd; do
        dig @8.8.8.8 "$sd" ANY >> "$dns"
    done < "$data_domain" &
    spinner $!
    wait
fi
echo -e "${yellow}[*]Finished DNS SCAN, output:$dir/dns.txt${reset}"

echo -e "${yellow}[*]Fetching Whois Information of $domain${reset}"
whois "$domain" | tee -a "$dir/whois.txt" > /dev/null &
spinner $!
wait
echo -e "${yellow}{*}Whois recon finished, stored in $dir/whois.txt${reset}"

echo "{~} Preparing mapped data"
amass enum -d "$domain" -o "$dir/mapped_data.txt" > /dev/null &
spinner $!
wait
echo "[*] Mapped Data Fetched"

echo -e "${blue}|====================================|${reset}"
echo -e "${green}|==========NETWORK SCANNING==========|${reset}"
echo -e "${blue}|====================================|${reset}"

echo "[*]Network Scanning In Progress ....."
echo "[*]Cleaning active domain file for effective scan results..."

if [ -s "$active_domain" ]; then
    sed -E 's#^https?://##' "$active_domain" | sed 's#/$##' > "$dir/cleaned.txt"
    sort -u "$dir/cleaned.txt" -o "$dir/cleaned.txt"
else
    : > "$dir/cleaned.txt"
fi

nout="$dir/network.txt"
: > "$nout"

tmp1="$(mktemp)"
nmap -sS -sV -O -Pn "$domain" -oN "$tmp1" > /dev/null &
spinner $!
wait
echo "[*]Now getting your file ready....."
{
    echo "Domain: $domain"
    grep "Nmap scan report for" "$tmp1"
    grep "open" "$tmp1"
    grep "OS details:" "$tmp1"
    echo "----------------------------------------------->>"
} >> "$nout"
rm -f "$tmp1"

if [ -s "$dir/cleaned.txt" ]; then
    while read -r subdomain; do
        [ -z "$subdomain" ] && continue
        echo "[/]Scanning $subdomain"
        tmp="$(mktemp)"
        nmap -sS -sV -O -Pn "$subdomain" -oN "$tmp" > /dev/null &
        spinner $!
        wait
        {
            echo ""
            echo "Subdomain: $subdomain"
            grep "Nmap scan report for" "$tmp"
            grep "open" "$tmp"
            grep "OS details:" "$tmp"
            echo "----------------------------------------------->>"
        } >> "$nout"
        rm -f "$tmp"
    done < "$dir/cleaned.txt"
fi

echo -e "${yellow}Network Scanning Finished, Data Stored in $nout${reset}"

echo -e "${red}About to run Nmap Script Engine (vuln/discovery/safe scripts) against all live hosts.${reset}"
echo -e "${red}Use Ctrl+C in the next 5 seconds to skip this step.${reset}"
sleep 5

if [ -s "$dir/cleaned.txt" ]; then
    while read -r subdomain; do
        [ -z "$subdomain" ] && continue
        echo "Scanning $subdomain"
        nmap -sS -sV -O -Pn --script=vuln --script=discovery --script=safe -n -T3 "$subdomain" -oN "$dir/nse.txt" &
        spinner $!
        wait
    done < "$dir/cleaned.txt"
fi

echo -e "${blue}[*] ALL SCANS ARE FINISHED. Outputs are in the $dir directory.${reset}"