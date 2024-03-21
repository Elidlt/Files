#!/bin/bash

# Path to the text file (replace "sources.txt" with your actual filename)
source_file="./content/sources.txt"

# Destination file (be cautious, this will overwrite existing content)
dest_file="/etc/apt/sources.list"

# Check if the source file exists
if [ ! -f "$source_file" ]; then
  echo "Error: File '$source_file' does not exist." && echo "" && echo "------------------------------------------" && echo ""
  exit 1  # Exit script with an error code
fi

# Copy the source file content to the destination file
# Use 'sudo' to gain root privileges for writing to /etc (caution!)
sudo cp "$source_file" "$dest_file"

# Check if the copy was successful
if [ $? -eq 0 ]; then
  echo "Successfully copied '$source_file' to '$dest_file'." && echo "" && echo "------------------------------------------" && echo ""
else
  echo "Error: Failed to copy the file." && echo "" && echo "------------------------------------------" && echo ""
  exit 1
fi

sudo apt update
sudo apt install resolvconf
sudo systemctl start resolvconf.service
sudo systemctl enable resolvconf.service
nameservers="nameserver 8.8.8.8\nnameserver 8.8.4.4"
dest_file="/etc/resolvconf/resolv.conf.d/head"
echo -e "$nameservers" >> "$dest_file"
if [ $? -eq 0 ]; then
  echo "Successfully appended nameservers to '$dest_file'." && echo "" && echo "------------------------------------------" && echo ""
  # Optional: Restart resolvconf service (recommended)
  sudo resolvconf --enable-updates 
  sudo resolvconf -u
  sudo systemctl restart resolvconf
else
  echo "Error: Failed to append nameservers." && echo "" && echo "------------------------------------------" && echo ""
  exit 1
fi


sudo apt update -y

# Get a list of packages to be upgraded with their versions
upgradable_packages=$(sudo apt list --gradable --quiet | awk '{print $1}')

if [[ -z "$upgradable_packages" ]]; then
  echo "No packages available for upgrade." && echo "" && echo "------------------------------------------" && echo ""
  exit 0
fi

# Inform the user about the packages to be upgraded
echo "The following packages will be upgraded:"
echo "$upgradable_packages"



if [[ "$confirm" =~ ^[Yy]$ || -z "$confirm" ]]; then
  sudo apt -y upgrade
  echo "Upgrade completed." && echo "" && echo "------------------------------------------" && echo ""
else
  echo "Upgrade cancelled." && echo "" && echo "------------------------------------------" && echo ""
  exit 1
fi

sudo iptables -F

# Reset UFW (automatically enters 'y' for confirmation)
echo "y" | sudo ufw --force reset

echo "iptables flushed and UFW reset." && echo "" && echo "------------------------------------------" && echo ""

sudo ufw allow 80/tcp
sudo ufw allow 22/tcp
sudo ufw allow 8080/tcp  # Allow TCP only for port 8080
sudo ufw allow 443

echo "rules Added to ufw"

target_file="/etc/ufw/sysctl.conf"
sed -i 's/#net\/ipv4\/ip_forward=1/net\/ipv4\/ip_forward=1/' "$target_file"
if [ $? -eq 0 ]; then
  echo "Successfully uncommented '#net/ipv4/ip_forward=1' in '$target_file'." && echo "" && echo "------------------------------------------" && echo ""
else
  echo "Error: Failed to uncomment the line." && echo "" && echo "------------------------------------------" && echo ""
fi

target_file="/etc/default/ufw"
sed -i 's/DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' "$target_file"
if [ $? -eq 0 ]; then
  echo "Successfully replaced 'DEFAULT_FORWARD_POLICY' with 'DROP' in '$target_file'." && echo "" && echo "------------------------------------------" && echo ""
else
  echo "Error: Failed to modify the file." && echo "" && echo "------------------------------------------" && echo ""
fi


packages="stunnel4 certbot ocserv"
sudo apt install -y $packages
if [ $? -eq 0 ]; then
  echo "Successfully installed packages: $packages." && echo "" && echo "------------------------------------------" && echo ""
else
  echo "Error: Failed to install one or more packages." && echo "" && echo "------------------------------------------" && echo ""
fi


commands=(
  "echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/60-custom.conf"
  "echo 'net.core.default_qdisc=fq' >> /etc/sysctl.d/60-custom.conf"
  "echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.d/60-custom.conf"
  "sysctl -p /etc/sysctl.d/60-custom.conf"
  "systemctl restart ufw"
)

for command in "${commands[@]}"; do
  echo "Executing: $command"
  eval "$command"

  if [ $? -ne 0 ]; then
    echo "Error: Command failed: $command"
    exit 1  # Exit with an error code
  fi
done

echo "All commands executed successfully." && echo "" && echo "------------------------------------------" && echo ""


echo "y" | sudo ufw --force enable

# Check if UFW was enabled successfully
if [ $? -eq 0 ]; then
  echo "UFW enabled successfully." && echo "" && echo "------------------------------------------" && echo ""
else
  echo "Error: Failed to enable UFW." && echo "" && echo "------------------------------------------" && echo ""
fi

while true; do
  read -p "Enter email address: " email

  if [[ "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
    break  # Email format is valid, exit the loop
  else
    echo "Invalid email format. Please enter a valid email address."
  fi
done

while true; do
  read -p "Enter Domestic host (e.g., example.com): " dom_host

  if [[ "$dom_host" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    break  # Host format is valid, exit the loop
  else
    echo "Invalid host format. Please enter a valid host name (letters, numbers, dots, and hyphens only)."
  fi
done

# Run certbot command with user-provided values
sudo certbot certonly --standalone \
                          --staple-ocsp \
                          --preferred-challenges http \
                          --agree-tos \
                          --email "$email" \
                          -d "$dom_host"

echo " Certification Recived Succesfully." && echo "" && echo "------------------------------------------" && echo ""

while true; do
  read -p "Enter Foreign Host Address (e.g., example.com:12345): " foreign_host_port

  if [[ "$foreign_host_port" =~ ^([a-zA-Z0-9.-]+):([0-9]+)$ ]]; then
    # Split into host and port
    foreign_host=${BASH_REMATCH[1]}
    fport=${BASH_REMATCH[2]}
    break  # Valid format, exit the loop
  else
    echo "Invalid format. Please enter 'Foreign_Host:Port' (letters, numbers, dots, hyphens for host, and numbers for port)."
  fi
done

while true; do
  read -p "Enter Domestic Host Port: " dom_port

  if [[ "$dom_port" =~ ^([0-9]+)$ ]]; then

    
    dom_port=$dom_port
    break  # Valid format, exit the loop
  else
    echo "Invalid format. Please enter Port between 1- 65335 ."
  fi
done

read -p "Enter tunnel name (letters, numbers, hyphens only): " tunnel_name

if [[ ! "$tunnel_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
  echo "Invalid tunnel name format. Please use letters, numbers, and hyphens."
  exit 1  # Exit script with error code for invalid tunnel name
fi

# Create and write configuration file
sudo touch /etc/stunnel/stunnel.conf  # Create file if it doesn't exist
sudo echo -e "[$tunnel_name]\nclient = yes\nverifyPeer = yes\naccept = $dom_port\nconnect = $foreign_host:$fport\nverifyPeer = yes\nCAfile = /etc/stunnel/ca-certificate.pem" > /etc/stunnel/stunnel.conf
cat /etc/letsencrypt/live/$dom_host/cert.pem /etc/letsencrypt/live/$dom_host/privkey.pem >> /etc/stunnel/stunnel.pem
echo "Stunnel configuration Done." && echo "" && echo "------------------------------------------" && echo ""



stunnel_service_content="[Unit]
Description=SSL tunnel for network daemons
After=network.target
After=syslog.target

[Install]
WantedBy=multi-user.target
Alias=stunnel.target

[Service]
Type=forking
ExecStart=/usr/bin/stunnel /etc/stunnel/stunnel.conf
ExecStop=/usr/bin/pkill stunnel

# Give up if ping don't get an answer
TimeoutSec=600

Restart=always
PrivateTmp=false
"
sudo sh -c "echo '$stunnel_service_content' > /usr/lib/systemd/system/stunnel.service"

echo "Stunnel service file created at /usr/lib/systemd/system/stunnel.service"
echo ""
sudo systemctl start stunnel4

service_status=$(sudo systemctl show -s stunnel4 | grep ActiveState | awk '{print $2}')

# Exit with error code (1) if not running
if [[ "$service_status" != "active" ]]; then
  echo "Error: Stunnel4 service is not running."
  exit 1
fi

sudo systemctl start stunnel.service
sudo systemctl enable stunnel.service

echo "Stunnel service started and enabled successfully." && echo "" && echo "------------------------------------------" && echo ""
