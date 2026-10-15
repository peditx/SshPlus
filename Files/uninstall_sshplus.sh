#!/bin/sh

# ==========================================
# PeDitXOS Tools - SSHPlus Uninstaller (v16)
# ==========================================
# Layout follows the "peditxos-app-maker" skill:
#   cron -> controller + view -> backend -> ACL -> UCI -> cache
#
# Shared packages (curl, openssh-client, procps-ng) are NEVER removed:
# other LuCI apps (especially PassWall) depend on them.
# --purge-deps ONLY removes sshpass (SSHPlus-specific).
# ==========================================

APP_NAME="sshplus"
UCI_CFG="sshplus"
SVC="/etc/init.d/sshplus"
PURGE_DEPS=0

for a in "$@"; do
	case "$a" in
		--purge-deps) PURGE_DEPS=1 ;;
	esac
done

echo ">>> Removing ${APP_NAME}..."

# 1. Stop and disable the service
echo "Stopping and disabling SSHPlus service..."
if [ -f "$SVC" ]; then
	"$SVC" stop  >/dev/null 2>&1 || true
	"$SVC" disable >/dev/null 2>&1 || true
fi
# make sure no leftover tunnel survives
pkill -f "/usr/bin/sshplus_service" 2>/dev/null
pkill -x sshpass 2>/dev/null
pkill -f "ssh .*-D 127.0.0.1" 2>/dev/null

# 2. Remove cron job
echo "Removing cron job..."
(crontab -l 2>/dev/null | grep -v "sshplus-backend") | crontab -

# 3. Remove PassWall / PassWall2 node
echo "Removing PassWall/PassWall2 configuration..."
for PCFG in passwall2 passwall; do
	if [ -f "/etc/config/$PCFG" ]; then
		uci -q delete "$PCFG.SshPlus"
		uci -q commit "$PCFG"
	fi
done

# 4. Remove service, daemon and backend
echo "Removing service scripts..."
rm -f "$SVC"
rm -f /usr/bin/sshplus
rm -f /usr/bin/sshplus_service
rm -f /usr/bin/sshplus-backend.sh
# pre-v16 leftovers
rm -f /etc/sshplus.conf

# 5. Remove UCI configuration
echo "Removing UCI configuration..."
uci -q delete "$UCI_CFG"
uci -q commit "$UCI_CFG" 2>/dev/null
rm -f "/etc/config/$UCI_CFG"

# 6. Remove LuCI files (current layout + pre-v16 leftovers)
echo "Removing LuCI interface files..."
rm -f "/usr/lib/lua/luci/controller/${APP_NAME}.lua"
rm -f "/usr/lib/lua/luci/model/cbi/${APP_NAME}_manager.lua"
rm -f "/usr/lib/lua/luci/model/cbi/${APP_NAME}_profiles.lua"
rm -rf "/usr/lib/lua/luci/view/${APP_NAME}"
rm -f "/usr/lib/lua/luci/view/${APP_NAME}_status_section.htm"

# 7. Remove rpcd ACL
echo "Removing rpcd ACL..."
rm -f "/usr/share/rpcd/acl.d/${APP_NAME}.json"
/etc/init.d/rpcd restart 2>/dev/null

# 8. Remove temp / state files
echo "Removing log and temporary files..."
rm -f /tmp/sshplus.log
rm -f /tmp/sshplus_start_time
rm -f /tmp/sshplus-status.json
rm -f /tmp/sshplus-ip.txt
rm -f /tmp/sshplus-ip.ts
rm -f /root/.ssh/sshplus_known_hosts

# 9. Optional: remove ONLY SSHPlus-specific packages (curl is NEVER removed - critical for PassWall)
if [ "$PURGE_DEPS" = "1" ]; then
	echo "Removing SSHPlus-specific packages (--purge-deps)..."
	echo "  Note: curl, openssh-client, procps-ng are KEPT (shared with other apps)."
	if command -v apk >/dev/null 2>&1; then
		apk del sshpass >/dev/null 2>&1 || true
	elif command -v opkg >/dev/null 2>&1; then
		opkg remove sshpass >/dev/null 2>&1 || true
	fi
else
	echo "Dependencies kept (curl / openssh-client / sshpass / procps-ng are shared)."
	echo "Use '--purge-deps' to remove ONLY sshpass (curl/openssh-client are NEVER removed)."
fi

# 10. Self-heal PassWall
# Older SSHPlus uninstallers removed `curl` outright, which leaves
# luci-app-passwall2's connectivity check permanently broken (HTTP 500 on
# connect_status). Uninstalling must not leave other apps broken.
if ! command -v curl >/dev/null 2>&1 && { [ -f /etc/config/passwall2 ] || [ -f /etc/config/passwall ]; }; then
	echo "Restoring 'curl' - PassWall needs it, older SSHPlus uninstallers removed it..."
	if command -v apk >/dev/null 2>&1; then
		apk add curl >/dev/null 2>&1 || true
	elif command -v opkg >/dev/null 2>&1; then
		opkg install curl >/dev/null 2>&1 || true
	fi
	if command -v curl >/dev/null 2>&1; then
		echo "  curl restored - PassWall's connectivity check works again."
	else
		echo "  WARNING: curl could not be installed. Run: apk add curl  |  opkg install curl"
	fi
fi

# 11. Clear LuCI caches
echo "Clearing LuCI cache..."
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache/* /tmp/luci-cache/* 2>/dev/null

echo ">>> SSHPlus has been completely uninstalled."
exit 0