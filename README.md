# Instant-Jump-Box
This repository aims to solve jumpbox problems once and for all, Idea is simple, setup an ovpn server with a bash script  and enable ssh on jumpbox machine with a service to ensure persistence of ovpn connection with another bash script.  


## Setting up VPN server 
- Sets up the OVPN server 
- Generates two clients (jumpbox.ovpn and client.ovpn) 
- Changes the rule so clients can communicate with each other 
 
Clone The repo and run the `setup_ovpnserver.sh` script with sudo 

```
sudo bash setup_ovpnserver.sh
```
use the jumpbox.ovpn file on jumpbox and client.ovpn file for attackers machine 

The VPN setup script uses https://github.com/hwdsl2/openvpn-install/ to set up a VPN server with 2 different client config "jumpbox.ovpn" and "client.ovpn" 


## Setting up the Jumpbox server 
- Creates a new user "tester" with password "hunter2"
- Enables SSH 
- Sets the ovpn as a service for persistence 


place the jumpbox.ovpn file in the same directory, download the script and run the `jumpbox_setup.sh` script with sudo

```
sudo bash jumpbox_setup.sh 
```
For removing the service and the user run 
```
sudo bash jumpbox_setup.sh --remove
```







