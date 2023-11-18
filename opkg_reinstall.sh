#!/bin/sh
trap "" SIGHUP
#
#
# Command line
## sh /root/opkg_reinstall_after_fw_upgrade/opkg_reinstall.sh force
#
# Notes
## This script automatically removes and install packages defined in vars after a firmware upgrade.
#
# Consts
PATH=/usr/bin:/usr/sbin:/sbin:/bin
#
# Note: If we log to "/root/" during "insmod", "opkg", "rmmod" commands affecting kernel modules, the kernel will panic and the device will reboot.
LOGFILE="/root/opkg_reinstall_after_fw_upgrade/opkg_reinstall.log"
LOG_MAX_LINES="1000"
#
LOG_COLLECTOR_HOSTNAME="OWRT-ROUTER"
PACKAGE_CACHE="/root/opkg_reinstall_after_fw_upgrade/packages"
#
# Runtime vars
INSTALL_ONLINE="1"
MINIMUM_UPTIME_IN_SECONDS="120"
REBOOT_REQUIRED="1"
PKG_TO_REMOVE=""
PKG_TO_INSTALL="luci-proto-wireguard kmod-wireguard wireguard-tools"
#
# Replace ct with non-ct WiFi drivers to fix stability issues, necessary f.e. on TP-Link Archer C7 devices.
INSTALL_NON_CT_WIFI_DRIVERS="0"
#
#
#
#
# -----------------------------------------------------
# -------------- START OF FUNCTION BLOCK --------------
# -----------------------------------------------------
logAdd () {
    TMP_DATETIME="$(date '+%Y-%m-%d [%H-%M-%S]')"
    TMP_LOGSTREAM="$(tail -n ${LOG_MAX_LINES} ${LOGFILE} 2>/dev/null)"
    echo "${TMP_LOGSTREAM}" > "$LOGFILE"
    echo "${TMP_DATETIME} $*" | tee -a "${LOGFILE}"
    return
}


waitForInternetConnection () {
    # Syntax:
    #   waitForInternetConnection
    #
    # Assume we can wait for internet connection if hostapd started fine.
    # If it did not start, we maybe miss internet connectivity via mesh.
    #
    if [ -z "$(iw dev)" ]; then
        logAdd "[INFO] WiFi is not initialized"
        return 1
    fi
    #
    # Give WiFi mesh interface time to connect and get internet connectivity.
    logAdd "[INFO] Waiting for WiFi to initialize"
    CURRENT_UPTIME_IN_SECONDS="$(cat /proc/uptime | cut -d "." -f 1)"
    SECONDS_TO_SLEEP="$((${MINIMUM_UPTIME_IN_SECONDS}-${CURRENT_UPTIME_IN_SECONDS}))"
    sleep "${SECONDS_TO_SLEEP}"
    #
    return 0
}


opkgRemove () {
    # Syntax:
    #   opkgRemove "[PACKAGE_NAME]"
    #
    for package_name in $@; do
        logAdd "[INFO] opkgRemove: Removing ${package_name}"
        RESULT="$(eval "opkg remove ${package_name}" 2>&1)"
        if ( echo "${package_name}" | grep -q "^kmod-" ); then
            REBOOT_REQUIRED="1"
            # logAdd "[INFO] opkgRemove: Kernel module removed. Will sleep a bit to avoid crash."
            sleep 10
        fi
        logAdd "[INFO] opkgRemove: - ${RESULT}"
        if ( echo "${RESULT}" | grep -q "Collected errors:"); then
            return 1
        fi
    done
    return 0
}


opkgInstall () {
    # Syntax:
    #   opkgInstall "[PACKAGE_NAME]"
    #
    # Online mode.
    if [ "${INSTALL_ONLINE}" = "1" ]; then
        RESULT="$(eval "opkg install ${@}" 2>&1)"
        logAdd "[INFO] opkgInstall: - ${RESULT}"
        if ( echo "${RESULT}" | grep -q "Collected errors:"); then
            return 1
        fi
        return 0
    fi
    #
    # Offline mode
    IPKG_FULLFN=""
    for package_name in $@; do
        if ( ! ls -1 ${PACKAGE_CACHE} | grep -q "^${package_name}_" ); then
            logAdd "[ERROR] opkgInstall: Package missing in cache - [${package_name}]"
            continue
        fi
        IPKG_FULLFN="${IPKG_FULLFN} ${PACKAGE_CACHE}/$(ls -1 ${PACKAGE_CACHE} | grep "^${package_name}_")"
    done
    if [ -z "${IPKG_FULLFN}" ]; then
        return 0
    fi
    RESULT="$(eval "opkg --cache ${PACKAGE_CACHE} install ${IPKG_FULLFN}" 2>&1)"
    if ( echo "${*}" | grep -q "kmod-" ); then
        REBOOT_REQUIRED="1"
        # logAdd "[INFO] opkgInstall: Kernel module added. Will sleep a bit to avoid crash."
        sleep 10
    fi
    logAdd "[INFO] opkgInstall: - ${RESULT}"
    if ( echo "${RESULT}" | grep -q "Collected errors:"); then
        return 1
    fi
    return 0
}


runInstall () {
    # Syntax:
    #   runInstall
    #
    # Global vars
    #   [IN] INSTALL_ONLINE
    #   [IN] PKG_TO_REMOVE
    #   [IN] PKG_TO_INSTALL
    #
    # If we are offline, check if we have a package cache available.
    if [ "${INSTALL_ONLINE}" = "0" ] && [ ! -d "${PACKAGE_CACHE}" ]; then
        logAdd "[ERROR] runInstall: We are offline but don't have a package cache available at ${PACKAGE_CACHE}"
        return 1
    fi
    #
    # If we are online, update the package cache.
    if [ "${INSTALL_ONLINE}" = "1" ]; then
        logAdd "[INFO] Synchronizing time to make certificate validation work ..."
		/usr/sbin/ntpd -p 0.openwrt.pool.ntp.org -nq 2>&1
        logAdd "[INFO] Downloading package information ..."
        RESULT="$(opkg update 2>&1)"
        if ( echo "${RESULT}" | grep -q "Failed to download"); then
			logAdd "[ERROR] opkg update: - ${RESULT}"
            return 1
        fi
        logAdd "[INFO] opkg update: - ${RESULT}"
    fi
    #
    # Replace ct with non-ct WiFi drivers
    if [ "${INSTALL_NON_CT_WIFI_DRIVERS}" = "1" ]; then
        # Remove order is important
        PKG_TO_REMOVE="${PKG_TO_REMOVE} kmod-ath10k-ct ath10k-firmware-qca988x-ct"
        PKG_TO_INSTALL="${PKG_TO_INSTALL} ath10k-firmware-qca988x kmod-ath10k"
    fi
    #
    # Remove defined packages
    logAdd "[INFO] runInstall: Remove packages"
    opkgRemove "${PKG_TO_REMOVE}"
    if [ ! "$?" = "0" ]; then
        return $?
    fi
    #
    # Install defined packages
    logAdd "[INFO] runInstall: Install packages"
    opkgInstall "${PKG_TO_INSTALL}"
    if [ ! "$?" = "0" ]; then
        return $?
    fi
    #
    return 0
}
# ---------------------------------------------------
# -------------- END OF FUNCTION BLOCK --------------
# ---------------------------------------------------
#
#
# Check command line.
if ( echo "${*}" | grep -q "force" ); then
    runInstall
    exit 0
fi
#
# Check if the script should run on boot.
if [ -f "/etc/_OPKG_REINSTALL_COMPLETE" ]; then
    echo "[INFO] /etc/_OPKG_REINSTALL_COMPLETE exists."
    exit 99
fi
#
waitForInternetConnection
#
logAdd "[INFO] Checking internet connection ..."
if ( ! echo -e "GET / HTTP/1.1\r\nHost: downloads.openwrt.org\r\n" | nc downloads.openwrt.org 80 > /dev/null ); then
    logAdd "[INFO] No internet connection. Switching to offline mode."
    INSTALL_ONLINE="0"
fi
#
runInstall
if [ ! "$?" = "0" ]; then
    logAdd "[ERROR] One or more packages FAILED to install"
else
    logAdd "[INFO] All packages installed successfully"
    touch "/etc/_OPKG_REINSTALL_COMPLETE"
fi
#
logAdd "[INFO] Cleanup"
if [ ! -z "${PACKAGE_CACHE}" ]; then
    rm -rf "${PACKAGE_CACHE}"
fi
#
if [ "${REBOOT_REQUIRED}" = "1" ]; then
    logAdd "[INFO] Rebooting device"
    reboot -d 3
    exit 0
fi
#
logAdd "[INFO] Done."
exit 0