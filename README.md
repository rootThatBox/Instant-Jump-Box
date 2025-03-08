# Instant-Jump-Box
This repository aims to solve jumpbox problems once and for all




## Setting up VPN server 
Clone The repo 
run the `setup_ovpnserver.sh` script with sudo 

```
sudo bash setup_ovpnserver.sh
```
use the jumpbox.ovpn file on jumpbox and client.ovpn file for attackers machine 

The VPN setup script uses https://github.com/hwdsl2/openvpn-install/ to set up a VPN server with 2 different client config "jumpbox.ovpn" and "client.ovpn" 





