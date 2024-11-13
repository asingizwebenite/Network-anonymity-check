#!/bin/bash




# Remote server credentials I used localhost for testing purposes but you can change the server as you wish.
REMOTE_USER="kali"
REMOTE_PASS="1234"
REMOTE_HOST="localhost"

# Generate a timestamp for unique filenames
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")S


# Function to install required applications if not already installed
install_application() {
    if ! command -v "$1" &> /dev/null; then
        echo "$1 not found. Installing..."
        sudo apt-get install -y "$1"
    else
        echo "$1 is already installed."
    fi
}

# Function to install and set up Nipe if not already installed
install_nipe() {
    if [ ! -d "/opt/nipe" ]; then
        echo "Nipe not found. Installing..."
        sudo apt-get update
        sudo apt-get install -y git perl
        sudo git clone https://github.com/htrgouvea/nipe /opt/nipe
        cd /opt/nipe || exit
        sudo cpan install Try::Tiny Config::Simple JSON
        sudo perl nipe.pl install
        echo "Nipe installed successfully."
    else
        echo "Nipe is already installed."
    fi
}

# Install required applications
install_application "sshpass"
install_application "nmap"
install_application "whois"
install_application "curl"
install_application "tor"
install_application "geoip-bin"
install_nipe

# Function to activate Nipe
activate_nipe() {
    cd /opt/nipe || exit
    sudo perl nipe.pl start
    sleep 10  
}

start_nipe() {
    echo "Attempting to start Nipe..."
    sudo perl /opt/nipe/nipe.pl start
    sleep 15  

    if pgrep -f "perl /opt/nipe/nipe.pl" > /dev/null; then
        echo "Nipe has started successfully."
        return 0  
    fi
    echo "Nipe did not start. Retrying..."
}

stop_nipe() {
    echo "Stopping Nipe..."
    cd /opt/nipe || exit
    sudo perl nipe.pl stop
    sleep 2  

    if ! pgrep -f "perl /opt/nipe/nipe.pl" > /dev/null; then
        echo "Nipe has stopped successfully."
    else
        echo "Failed to stop Nipe. Exiting..."
        exit 1
    fi
}

check_anonymity() {
    stop_nipe

    true_ip=$(curl -s ifconfig.me)
    true_country=$(whois "$true_ip" | grep -i "country" | head -n 1 | awk '{print $2}')

    if [[ -z "$true_country" ]]; then
        echo "Unable to detect the country for your true IP. Exiting."
        exit 1
    fi
    echo "Your true country is: $true_country (IP: $true_ip)"

    start_nipe
    sleep 10  

    anonymous_ip=$(curl -s ifconfig.me)
    anonymous_country=$(geoiplookup $anonymous_ip | grep -i "country" | awk '{print $4}' | tr -d ',')

    if [[ -z "$anonymous_country" ]]; then
        echo "Unable to detect the country for the anonymized IP. Exiting."
        exit 1
    fi
    echo "Your anonymous country is: $anonymous_country (IP: $anonymous_ip)"

    if [[ "$true_country" == "$anonymous_country" ]]; then
        echo "Warning: You are not anonymous. Your country appears the same before and after using Nipe."
        exit 1
    else
        echo "You are anonymous. Location has changed from $true_country to $anonymous_country."
    fi
}

# Run the anonymity check
check_anonymity

read -p "Enter the address to scan: " TARGET_ADDRESS

# modify TARGET_ADDRESS to use it in filenames  by replacing dots with underscores
SAFE_TARGET_ADDRESS=$(echo "$TARGET_ADDRESS" | tr '.' '_')

# SSH function to run commands on the remote server
remote_command() {
    local command="$1"
    sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_HOST" "$command"
}
remote_details() {
    # Get the public IP address of the remote server
    remote_ip=$(remote_command "curl -s https://ipinfo.io/ip")
    
    # If we fail to retrieve the IP address, exit with an error message
    if [ -z "$remote_ip" ]; then
        echo "Error: Unable to retrieve remote IP address."
        exit 1
    fi
      
   
    # Get the country information using geoiplookup
    remote_country=$(remote_command "geoiplookup $remote_ip | grep -i 'country' | awk '{print \$5}'")

    # If country lookup fails tell the user that we weren't able to get the country
    if [ -z "$remote_country" ]; then
        remote_country="couldn't get the country"
    fi

    # Get the system uptime
    remote_uptime=$(remote_command "uptime -p")

    # Output the details
    echo "Remote Server Details:"
    echo "Country: $remote_country"
    echo "IP Address: $remote_ip"
    echo "Uptime: $remote_uptime"
}


# Function to install required applications if not already installed on the remote server
install_application_remote() {
    local app_name="$1"
    sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_HOST" "
        if ! command -v $app_name &> /dev/null; then
            echo \"$app_name not found. Installing...\"
            echo \"$REMOTE_PASS\" | sudo -S apt-get install -y $app_name
        else
            echo \"$app_name is already installed.\"
        fi
    "
}
echo "installing the applications on the remote server"
# Install required applications on the remote server
install_application_remote "whois"
install_application_remote "nmap"
install_application_remote "curl"
install_application_remote "geoip-bin"
install_application_remote "sshpass"


# Call the function to print the remote details
remote_details


# Define output directory
OUTPUT_DIR="/home/kali"


# Running Whois and Nmap scan on the target address from the remote server
scan_target_address() {
    echo "Running Whois on $TARGET_ADDRESS from remote server..."
    remote_command "whois $TARGET_ADDRESS" > "$OUTPUT_DIR/whois_result_${SAFE_TARGET_ADDRESS}.txt"
    echo "Whois result saved to $OUTPUT_DIR/whois_result_${SAFE_TARGET_ADDRESS}.txt"

    echo "Running Nmap on $TARGET_ADDRESS from remote server..."
    remote_command "nmap -Pn $TARGET_ADDRESS" > "$OUTPUT_DIR/nmap_result_${SAFE_TARGET_ADDRESS}.txt"
    echo "Nmap result saved to $OUTPUT_DIR/nmap_result_${SAFE_TARGET_ADDRESS}.txt"
}

# Log the actions taken in the same file actions_log.txt to be able to see the scannings that took place in the same file for ease of understing
log_action() {
    echo "$(date): Scanned target address - ${SAFE_TARGET_ADDRESS}" >> "${OUTPUT_DIR}/actions_log.txt"
    echo "logged actions to ${OUTPUT_DIR}/actions_log.txt"
}

# Scan the target address on the remote server and log the actions
scan_target_address
log_action