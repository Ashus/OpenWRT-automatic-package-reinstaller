# OpenWRT automatic package reinstaller
This script reinstalls critical packages after you upgrade your OpenWRT so you can get back to them remotely.

# Installation

## 01  Upload the script
- place script in /root/opkg_reinstall_after_fw_upgrade/opkg_reinstall.sh

## 02  Let the script know to not launch with current system and add execute bit
 -run in terminal:
```
touch "/etc/_OPKG_REINSTALL_COMPLETE"
chmod 0755 /root/opkg_reinstall_after_fw_upgrade/opkg_reinstall.sh
```

## 03  Edit /etc/sysupgrade.conf
- add directory /root

```
## This file contains files and directories that should
## be preserved during an upgrade.

# /etc/example.conf
# /etc/openvpn/

/root
```

## 04  Edit /etc/rc.local
```
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

( /bin/sleep 30; /bin/sh /root/opkg_reinstall_after_fw_upgrade/opkg_reinstall.sh ) &

exit 0
```

# Flash new firmware image
- retain the settings


# Customization
- add or remove packages, make sure all of them are available
- if your wifi is not configured, please remove the `waitForInternetConnection` at the bottom of the file


# Tips
- check logs after each update
- if you have the option, try new OpenWRT versions first on remote locations you have other means of access to (eg. public IPv6, physical closeness)
- try the script before you depend on it


# Credits
- Catfriend1 @ https://forum.openwrt.org/u/catfriend1 for the original script
- TheHellSite @ https://forum.openwrt.org/u/TheHellSite for improvements
- Ashus @ https://github.com/Ashus for more improvements
- sourced from https://forum.openwrt.org/t/automatic-update-script/75193