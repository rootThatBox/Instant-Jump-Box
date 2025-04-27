#!/bin/bash

# Disable exit on error to handle package failures gracefully
set -e

# Variables
USERNAME="tester"
PASSWORD="hunter2"
OVPN_FILE="/etc/jumpbox.ovpn"
SERVICE_NAME="ovpnforever"
PUBKEY_SRC="/usr/ssh.pub"
PRIVKEY_SRC="/usr/ssh"

# Function to check network connectivity
check_network() {
    echo "[*] Checking network connectivity..."
    for i in {1..30}; do
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            echo "[*] Network is up"
            return 0
        fi
        sleep 1
    done
    echo "[WARNING] Network not available after 30 seconds"
    return 1
}

# Check if script is run with sudo
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run with sudo privileges"
    exit 1
fi

echo "[*] Creating user $USERNAME..."
if ! id "$USERNAME" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
    usermod -aG sudo "$USERNAME"
    echo "[*] User $USERNAME created and added to sudo group"
else
    echo "[*] User $USERNAME already exists"
fi

echo "[*] Installing necessary packages..."
if check_network; then
    apt-get update || echo "[WARNING] apt-get update failed"
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        openssh-server \
        openvpn \
        ufw \
        curl \
        wget \
        ca-certificates \
        systemd-networkd || echo "[WARNING] Package installation failed"
else
    echo "[WARNING] Skipping package installation due to no network"
fi

echo "[*] Enabling network wait service..."
systemctl enable systemd-networkd-wait-online.service || echo "[WARNING] Failed to enable network wait service"

echo "[*] Configuring SSH for key-based access only..."

# Generate SSH host keys if missing
ssh-keygen -A || echo "[WARNING] Failed to generate SSH host keys"

# Update sshd_config for key-based login only (no passwords)
echo "[*] Updating SSH configuration for key-only login..."
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
sed -i 's/^#\?Port.*/Port 22/' /etc/ssh/sshd_config

# Allow only the tester user
if ! grep -q "AllowUsers $USERNAME" /etc/ssh/sshd_config; then
    echo "AllowUsers $USERNAME" >> /etc/ssh/sshd_config
fi

# Setup SSH directory and copy keys
echo "[*] Setting up SSH key directory for $USERNAME..."
sudo -u "$USERNAME" mkdir -p "/home/$USERNAME/.ssh"
chmod 700 "/home/$USERNAME/.ssh"
echo "[*] Copying SSH public key..."
cp "$PUBKEY_SRC" "/home/$USERNAME/.ssh/authorized_keys"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh/authorized_keys"

# Optional: Copy private key (only if required by your use case)
# echo "[*] Copying SSH private key..."
# cp "$PRIVKEY_SRC" "/home/$USERNAME/.ssh/id_ed25519"
# chmod 600 "/home/$USERNAME/.ssh/id_ed25519"
# chown "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh/id_ed25519"

# Enable and start SSH service
systemctl enable ssh || echo "[WARNING] Failed to enable SSH service"
systemctl restart ssh || echo "[WARNING] Failed to restart SSH service"

if systemctl is-active ssh >/dev/null; then
    echo "[*] SSH service is active with key-only login for $USERNAME"
else
    echo "[ERROR] SSH service failed to start"
fi

echo "[*] Copying VPN config..."
if [[ -f "$OVPN_FILE" ]]; then
    install -m 600 "$OVPN_FILE" /etc/openvpn/jumpbox.ovpn
    chown root:root /etc/openvpn/jumpbox.ovpn
    echo "[*] VPN config copied to /etc/openvpn/jumpbox.ovpn"
else
    echo "[WARNING] OVPN file not found at $OVPN_FILE. You must copy it post-boot."
fi

echo "[*] Creating systemd service for OpenVPN..."
cat << EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Persistent OpenVPN Connection for Jumpbox
After=network-online.target systemd-networkd-wait-online.service
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
ExecStart=/usr/sbin/openvpn --config /etc/openvpn/jumpbox.ovpn
Restart=always
RestartSec=10
User=root
Group=root
WorkingDirectory=/etc/openvpn
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "[*] Enabling OpenVPN systemd service..."
systemctl enable $SERVICE_NAME || echo "[WARNING] Failed to enable OpenVPN service"
systemctl start $SERVICE_NAME || echo "[WARNING] Failed to start OpenVPN service"
if systemctl is-active $SERVICE_NAME >/dev/null; then
    echo "[*] OpenVPN service is active"
else
    echo "[ERROR] OpenVPN service failed to start"
fi

echo "[*] Preventing sleep/hibernate..."
cat << EOF > /etc/systemd/logind.conf
HandleSuspendKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleHibernateKey=ignore
HandlePowerKey=ignore
IdleAction=ignore
EOF
mkdir -p /etc/systemd/system/{sleep.target,suspend.target,hibernate.target,hybrid-sleep.target}
for target in sleep suspend hibernate hybrid-sleep; do
    ln -sf /dev/null "/etc/systemd/system/${target}.target"
done

echo "[*] Enabling UFW firewall..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp  # Explicitly allow SSH
    ufw allow 1194/udp  # Allow OpenVPN (adjust if different port/protocol)
    ufw --force enable
    if ufw status | grep -q "Status: active"; then
        echo "[*] UFW firewall is active with SSH and OpenVPN ports open"
    else
        echo "[ERROR] UFW firewall failed to enable"
    fi
else
    echo "[WARNING] UFW not installed, skipping firewall configuration"
fi

echo "[*] Applying kernel hardening settings..."
cat << EOF > /etc/sysctl.d/99-hardening.conf
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
EOF
sysctl -p /etc/sysctl.d/99-hardening.conf || echo "[WARNING] Failed to apply kernel hardening"

echo "[*] Cleaning unnecessary packages..."
UNNEEDED_PKGS="telnet ftp rsh rlogin talk"
for pkg in $UNNEEDED_PKGS; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        apt-get remove --purge -y "$pkg" || echo "[WARNING] Failed to remove $pkg"
    fi
done
apt-get autoremove -y || echo "[WARNING] Failed to autoremove packages"

echo "[*] Done. SSH key-only login for '$USERNAME' is configured and active."
exit 0
