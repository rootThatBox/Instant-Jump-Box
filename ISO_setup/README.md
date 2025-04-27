# ISO Building Setup

Follow these steps to build a custom Kali Linux ISO.

## 1. Install Required Packages

On a Kali Linux or Debian-based system, run:

```bash
sudo apt update
sudo apt install -y git live-build simple-cdd cdebootstrap curl
```

## 2. Clone the Kali Live Build Configuration Repository

Clone the official Kali Linux live-build configuration repository:

```bash
git clone https://gitlab.com/kalilinux/build-scripts/live-build-config.git
```

Reference: [Kali Linux Documentation — Live Build a Custom Kali ISO](https://www.kali.org/docs/development/live-build-a-custom-kali-iso/)

## 3. Add Custom Files

- Copy `jumpbox_iso.sh` and your `ssh.pub` file into:

  ```text
  live-build-config/kali-config/common/includes.chroot/usr/
  ```

- Copy your `jumpbox.ovpn` file into:

  ```text
  live-build-config/kali-config/common/includes.chroot/etc/
  ```

- Edit the following file:

  ```text
  live-build-config/kali-config/common/hooks/live/kali-hacks.chroot
  ```

  Append this line at the end of the file:

  ```bash
  sudo bash /etc/jumpbox_iso.sh
  ```

## 4. Build the Custom ISO

Navigate into the cloned repository directory:

```bash
cd live-build-config
```

Then build the ISO with:

```bash
./build.sh -v
```

Wait for the build process to complete.  
The final ISO will be generated after successful completion.

