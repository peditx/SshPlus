#!/bin/sh

echo "Starting SSHPlus uninstallation..."

# 1. Stop and disable the service
echo "Stopping and disabling SSHPlus service..."
if [ -f /etc/init.d/sshplus ]; then
    /etc/init.d/sshplus stop >/dev/null 2>&1 || true
    /etc/init.d/sshplus disable >/dev/null 2>&1 || true
fi

# 2. Remove Passwall/Passwall2 configuration
echo "Removing Passwall/Passwall2 configuration..."
if uci show passwall2 >/dev/null 2>&1; then
    uci -q delete passwall2.SshPlus
    uci commit passwall2
fi
if uci show passwall >/dev/null 2>&1; then
    uci -q delete passwall.SshPlus
    uci commit passwall
fi

# 3. Remove service and binary files
echo "Removing service scripts..."
rm -f /etc/init.d/sshplus
rm -f /usr/bin/sshplus_service

# 4. Remove configuration file
echo "Removing UCI configuration..."
rm -f /etc/config/sshplus

# 5. Remove LuCI files
echo "Removing LuCI interface files..."
rm -f /usr/lib/lua/luci/controller/sshplus.lua
rm -f /usr/lib/lua/luci/model/cbi/sshplus_manager.lua
rm -f /usr/lib/lua/luci/view/sshplus_status_section.htm

# 6. Remove temporary log files
echo "Removing log and temporary files..."
rm -f /tmp/sshplus.log
rm -f /tmp/sshplus_start_time

# 7. Uninstall packages
echo "Removing installed packages..."
opkg remove curl openssh-client openssh-client-utils sshpass procps-ng-pkill procps-ng-pgrep >/dev/null 2>&1 || true

# 8. Clean LuCI cache
echo "Clearing LuCI cache..."
rm -f /tmp/luci-indexcache

echo "SSHPlus has been completely uninstalled."

exit 0
