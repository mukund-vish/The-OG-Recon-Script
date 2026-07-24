#!/bin/bash
export PATH=$PATH:~/go/bin
export PATH=$PATH:$(go env GOPATH)/bin
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc

red="\033[31m"
green="\033[32m"
yellow="\033[33m"
blue="\033[34m"
reset="\033[0m"

cleanup() {
    echo -e "\n$Scan(s) interrupted output(if generated) stored in $dir${reset}"
    echo -e "${blue}Thank you for using OG-RECON!${reset}"
    exit 1
}

trap cleanup SIGINT

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid &>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "         \b\b\b"
}
domain=$1
dir=$domain
mkdir -p $dir

clear
echo -e "${blue}"
toilet -f slant "OG-RECON" --filter border
echo -e "${reset}"
echo -e "${green}"
toilet -f term "Created by Mukund Vishwakarma | Version:1.0"
echo -e "${reset}"
echo -e "${blue}"
toilet -f term "Target:$domain" --filter border
echo -e "${reset}"
echo -e "${blue}|====================================|${reset}"
echo -e "${green}|======Initializing DOMAIN RECON=====|${reset}"
echo -e "${blue}|====================================|${reset}"

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Finding Sub domain"
echo -e "${red}|--------------------------------------------------|${reset}"

subdomains="$dir/subdomains.txt"
subfinder -d $domain -o $subdomains -silent &
spinner $!
wait

sort -u $subdomains -o $subdomains
if [ -s "$subdomains" ];then
	no_subdomains=$(wc -l < "$subdomains")
	echo -e "${yellow}[*]Subdomains Found, stored in $subdomains${reset} Total:${red}$no_subdomains${reset}"
else
	echo -e  "${red}[*]No subdomains were found${reset}"
fi

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Finding Sub-Sub domain"
echo -e "${red}|--------------------------------------------------|${reset}"

subsubdomains="$dir/subsubdomains.txt"
subfinder -dL $subdomains -o $subsubdomains -silent &
spinner $!
wait
if [ -s "$subsubdomains" ];then
        no_subsubdomains=$(wc -l < "$subsubdomains")
        echo -e "${yellow}[*]Sub-Sub Domains Found, stored in $subsubdomains Total:$no_subsubdomains${reset}"
else
        echo -e "${red}[*]No Sub-Sub Domains  were found${reset}"
fi

echo -e "${yellow}{*}Merging Both files.......${reset}"
data_domain="$dir/datadom.txt"
cat $subdomains > $data_domain
cat $subsubdomains >> $data_domain
echo -e "${yellow}{*}File Merged into $data_domain${reset}"

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Performing a Recursive scan ....."
echo -e "${red}|--------------------------------------------------|${reset}"

recursive="$dir/recursive.txt"
subfinder -dL $data_domain -o $recursive -recursive -silent &
spinner $!
wait

if [ -s "$recursive" ];then
        no_recursive=$(wc -l < "$recursive")
        echo -e "${yellow}[*]Subdomains Found, stored in $recursive Total:$no_recursive${reset}"
else
        echo -e "${red}[*]No subdomains were found${reset}"
fi

echo -e "${yellow}{*}Cleaning and Merging ......${reset}"
cat $recursive >> $data_domain
if [ $(wc -l < $data_domain) -gt 1 ];then
	sort -u $data_domain -o $data_domain &
	spinner $!
	wait
else
	echo -e "${blue}{}File does not require cleanning, Skipping it${reset}"
fi
echo -e "${yellow}{*}Cleaning and Merging Finished${reset}"

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Finding Active Subdomains.........."
echo -e "${red}|--------------------------------------------------|${reset}"
active_domain="$dir/active.txt"
cat $data_domain | httprobe > $active_domain &
spinner $!
wait

if [ -s "$active_domain" ];then
        no_active=$(wc -l < "$active_domain")
	real_number=$((no_active / 2))
        echo -e "${yellow}[*]Active SubDomains, stored in $active_domain Total:$real_number${reset}"
else
        echo -e "${red}{*}No Active subdomains were found${reset}"
fi

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Addtional Scan"
echo -e "${red}|--------------------------------------------------|${reset}"

assetfinder $domain > "$dir/additional" &
spinner $!
wait

echo -e "${yellow}[*]Additional Scan finished, Results stored in $dir/additional${reset}"


echo -e "${red}|--------------------------------------------------|${reset}"
echo -e "${blue} DOMAIN STATS ${reset}"
echo -e "${green}------>${reset}Total Subdomains:${red}$no_subdomains${reset}"
echo -e  "${green}------->${reset}Total Active Subdomains:${red}$real_number${reset}"
echo -e "${red}|--------------------------------------------------|${reset}"

echo -e "${red}|--------------------------------------------------|${reset}"
echo "Domain Scan Finished..........."
echo -e "${red}|--------------------------------------------------|${reset}"

echo -e "${blue}|====================================|${reset}"
echo -e "${green}|===Initializing Additional RECON===|${reset}"
echo -e "${blue}|====================================|${reset}"


echo -e "${yellow}[*]Finding Paramters for Domain......${reset}"
paramspider -d $domain > /dev/null &
spinner $!
wait
mv "results/$domain.txt" "$dir"
echo -e "${green}[..]REAL OUTPUT STORED IN $dir/$domain.txt${reset}"

echo -e "${yellow}[*]Finding DNS records for domain and Subdomains${reset}"
dns="$dir/dns.txt"
dig @8.8.8.8 $domain > $dns &
spinner $!
wait
cat $data_domain | xargs -I{} dig @8.8.8.8 ANY >> $dns &
spinner $!
wait
echo -e "${yellow}[*]Finished DNS SCAN, output:$dir/dns.txt${reset}"


echo -e "${yellow}[*]Fetching Whois Information of $domain${reset}"
whois $domain | tee -a "$dir/whois.txt" > /dev/null &
spinner $!
wait
echo -e "${yellow}{*}Whois recon finished, stored in $dir/whois.txt${reset}"

echo "{~} Prepearing mapped data"
amass enum -d $domain -o maped_data.txt > /dev/null &
spinner $!
wait
echo "[*] Mapped Data Fetched"

echo -e "${blue}|====================================|${reset}"
echo -e "${green}|==========NETWORK SCANNING==========|${reset}"
echo -e "${blue}|====================================|${reset}"


echo "[*]Network Scanning In Progress ....."
echo "[*]Cleaning active domain file for effective scan results..."

sed 's/^http[s]*:\/\///' "$dir/active.txt" > "$dir/cleaned.txt"
sort -u "$dir/cleaned.txt" -o "$dir/cleaned.txt"

nout="$dir/network.txt"
nmap -sS -sV -O -Pn $domain -oN temp1.txt > /dev/null &
spinner $!
wait
echo "[*]Now getting your file ready....."
echo "Domain: $Domain">>$nout
grep "Nmap scan report for" temp1.txt >> $nout
grep "open" temp1.txt >> $nout
grep "OS details:" temp1.txt >> $nout
echo "----------------------------------------------->>">> $nout
rm temp1.txt

while read -r subdomain; do
	echo "[/]Scaning $subdomain"
	nmap -sS -sV -O -Pn "$subdomain" -oN temp.txt > /dev/null &
	spinner $!
	wait
	echo -e "\n" >> "$nout"
	echo "Subdomain: $subdomain">>$nout
	grep "Nmap scan report for" temp.txt >> $nout
	grep "open" temp.txt >> $nout
	grep "OS details:" temp.txt >> $nout
	echo "----------------------------------------------->>">> $nout
	rm temp.txt
	done < "$dir/cleaned.txt"

echo -e "${yellow}Network Scanning Finished, Data Stored in $nout${reset}"

echo -e "${red}Using Nmap Script Engine , Use ctrl+c to terminate if do not want this action${reset}"
sleep 5
while read -r subdomain; do
        echo "Scaning $subdomain"
        nmap -sS -sV -O -Pn --script=vuln --script=discovery --script=safe -n -T3  "$subdomain" -oN $dir/nse.txt &
	spinner $!
	wait
 done < "$dir/cleaned.txt"

echo -e "${blue}[]ALL SCANS ARE FINISHED YOU CAN SEE ALL THE OUTPUTS IN $dir DIRECTORY${reset}"
