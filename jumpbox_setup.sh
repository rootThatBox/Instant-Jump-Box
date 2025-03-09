#!/bin/bash

# Check if script is run with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo privileges"
   exit 1
fi

# Variables
USERNAME="tester"
PASSWORD="hunter2"
OVPN_FILE="jumpbox.ovpn"
SERVICE_NAME="ovpnforever"

# Function to set up everything
setup() {
    echo "Setting up the environment..."
    echo "Enabled Lingering"
    sudo loginctl enable-linger root
#    sudo loginctl enable-linger tester

    # Create user if it doesn't exist
    if ! id "$USERNAME" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$USERNAME"
        echo "Created user $USERNAME"
    fi

    # Set password
    echo "$USERNAME:$PASSWORD" | chpasswd
    echo "Set password for $USERNAME"

    # Add user to sudo group
    usermod -aG sudo "$USERNAME"
    echo "Added $USERNAME to sudo group"

    # Install OpenSSH if not installed
    if ! dpkg -l | grep -q openssh-server; then
        apt-get update
        apt-get install -y openssh-server
    fi

    # Enable and start SSH
    systemctl enable ssh
    systemctl start ssh
    echo "SSH server enabled and started"

    # Allow tester user in SSH config
    if ! grep -q "AllowUsers $USERNAME" /etc/ssh/sshd_config; then
        echo "AllowUsers $USERNAME" >> /etc/ssh/sshd_config
        systemctl restart ssh
        echo "Configured SSH to allow $USERNAME"
    fi

    # Check if jumpbox.ovpn exists
    if [ ! -f "$OVPN_FILE" ]; then
        echo "Error: $OVPN_FILE not found in current directory"
        exit 1
    fi

    # Install OpenVPN if not installed
    if ! dpkg -l | grep -q openvpn; then
        apt-get update
        apt-get install -y openvpn
    fi

    # Create OpenVPN service file with DCO disabled
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOL
[Unit]
Description=Persistent OpenVPN Connection for Jumpbox
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/sbin/openvpn --config /etc/openvpn/$OVPN_FILE 
Restart=always
RestartSec=60
User=root
Group=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW

[Install]
WantedBy=multi-user.target
EOL


# Disable Sleep thorugh logind.conf 
    cat <<EOL | sudo tee -a /etc/systemd/logind.conf
HandleSuspendKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleHibernateKey=ignore
HandlePowerKey=ignore
IdleAction=ignore
EOL

    # Copy OVPN file and set up persistent VPN
    cp "$OVPN_FILE" /etc/openvpn/ || { echo "Failed to copy $OVPN_FILE"; exit 1; }
    chmod 600 /etc/openvpn/$OVPN_FILE

    # Reload systemd and start service
    systemctl daemon-reload || { echo "Failed to reload systemd"; exit 1; }
    systemctl enable $SERVICE_NAME || { echo "Failed to enable $SERVICE_NAME"; exit 1; }
    systemctl start $SERVICE_NAME || { echo "Failed to start $SERVICE_NAME"; exit 1; }
    sudo loginctl enable-linger tester
    # Verify VPN is up
    sleep 5
    if ip link show tun0 >/dev/null 2>&1; then
        echo "Persistent VPN connection set up successfully"
    else
        echo "Failed to establish VPN connection. Check logs with 'journalctl -u $SERVICE_NAME'"
        exit 1
    fi
}

# Function to remove everything
remove() {
    echo "Removing all changes..."
    echo "Disabled Lingering"
    sudo loginctl disable-linger root
    sudo loginctl disable-linger tester
    # Stop and disable VPN service
  #  if systemctl is-active $SERVICE_NAME >/dev/null 2>&1; then
    systemctl stop $SERVICE_NAME
    systemctl disable $SERVICE_NAME
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    rm -f /etc/openvpn/$OVPN_FILE
    systemctl daemon-reload
    echo "Removed VPN service"
   # fi

    # Remove SSH AllowUsers entry
    if grep -q "AllowUsers $USERNAME" /etc/ssh/sshd_config; then
        sed -i "/AllowUsers $USERNAME/d" /etc/ssh/sshd_config
        systemctl restart ssh
        echo "Removed SSH access for $USERNAME"
    fi

    # Remove user if it exists
    if id "$USERNAME" >/dev/null 2>&1; then
        userdel -r "$USERNAME"
        echo "Removed user $USERNAME"
    fi
    #Remove Sleep Config
    sed -i '/HandleSuspendKey=ignore/d' /etc/systemd/logind.conf
    sed -i '/HandleLidSwitch=ignore/d' /etc/systemd/logind.conf
    sed -i '/HandleLidSwitchDocked=ignore/d' /etc/systemd/logind.conf
    sed -i '/HandleHibernateKey=ignore/d' /etc/systemd/logind.conf
    sed -i '/HandlePowerKey=ignore/d' /etc/systemd/logind.conf


}

# Main logic
case "$1" in
    "--remove")
        remove
        ;;
    "")
        setup
        ;;
    *)
        echo "Usage: $0 [--remove]"
        echo "  No arguments: Set up the environment"
        echo "  --remove: Remove all changes"
        exit 1
        ;;
esac



echo "Operation completed successfully"
exit 0
