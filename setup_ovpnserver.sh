wget https://raw.githubusercontent.com/hwdsl2/openvpn-install/master/openvpn-install.sh
if [[ "$1" == "--remove" ]]; then
    sudo bash openvpn-install.sh --uninstall  -y 
    echo "THE OVPN SERVER IS REMOVED"
    exit 0
fi


bash openvpn-install.sh --auto
bash openvpn-install.sh --addclient jumpbox
###Remove Firewall Rules set by auto install

remove_firewall_rules() {
	port=$(grep '^port ' "$OVPN_CONF" | cut -d " " -f 2)
	protocol=$(grep '^proto ' "$OVPN_CONF" | cut -d " " -f 2)
	if systemctl is-active --quiet firewalld.service; then
		ip=$(firewall-cmd --direct --get-rules ipv4 nat POSTROUTING | grep '\-s 10.8.0.0/24 '"'"'!'"'"' -d 10.8.0.0/24' | grep -oE '[^ ]+$')
		# Using both permanent and not permanent rules to avoid a firewalld reload.
		firewall-cmd -q --remove-port="$port"/"$protocol"
		firewall-cmd -q --zone=trusted --remove-source=10.8.0.0/24
		firewall-cmd -q --permanent --remove-port="$port"/"$protocol"
		firewall-cmd -q --permanent --zone=trusted --remove-source=10.8.0.0/24
		firewall-cmd -q --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j MASQUERADE
		firewall-cmd -q --permanent --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j MASQUERADE
		if grep -qs "server-ipv6" "$OVPN_CONF"; then
			ip6=$(firewall-cmd --direct --get-rules ipv6 nat POSTROUTING | grep '\-s fddd:1194:1194:1194::/64 '"'"'!'"'"' -d fddd:1194:1194:1194::/64' | grep -oE '[^ ]+$')
			firewall-cmd -q --zone=trusted --remove-source=fddd:1194:1194:1194::/64
			firewall-cmd -q --permanent --zone=trusted --remove-source=fddd:1194:1194:1194::/64
			firewall-cmd -q --direct --remove-rule ipv6 nat POSTROUTING 0 -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j MASQUERADE
			firewall-cmd -q --permanent --direct --remove-rule ipv6 nat POSTROUTING 0 -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j MASQUERADE
		fi
	else
		systemctl disable --now openvpn-iptables.service
		rm -f /etc/systemd/system/openvpn-iptables.service
	fi
	if sestatus 2>/dev/null | grep "Current mode" | grep -q "enforcing" && [[ "$port" != 1194 ]]; then
		semanage port -d -t openvpn_port_t -p "$protocol" "$port"
	fi
}

sleep 5

echo "REMOVED FIREWALL RULES OF VPN INSTALL"
remove_firewall_rules


sudo iptables -A FORWARD -i tun0 -o tun0 -j ACCEPT
sudo iptables -A FORWARD -i tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT

sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE

#ADDING MTU PARAMETER ON CLIENT FOR STABILITY 
sed -i '3a mssfix 1400' /root/client.ovpn
sed -i '3a mssfix 1400' /root/jumpbox.ovpn
sed -i '9a keepalive 10 60' /root/jumpbox.ovpn
sed -i '/persist-key/d;/persist-tun/d' /root/jumpbox.ovpn

