#!/bin/sh

# PeDitXOS Tools - SSHPlus Installer (v15 - Final Banner)
# This script installs the SSHPlus service and its LuCI interface.
# Fixes: Adds a final ASCII art banner upon successful installation.

echo ">>> Starting SSHPlus Installation (v15 Final Banner)..."

# Create config file if it doesn't exist
echo "Creating configuration file..."
[ -f /etc/config/sshplus ] || cat > /etc/config/sshplus <<'EoL'
config sshplus 'global'
	option active_profile ''
config profile
	option host 'host.example.com'
	option user 'root'
	option port '22'
	option auth_method 'password'
	option pass 'your_password'
	option key_file '/root/.ssh/id_rsa'
EoL

# Make opkg output visible for easier debugging.
echo "Updating package lists..."
opkg update
if [ $? -ne 0 ]; then
    echo "--------------------------------------------------"
    echo "ERROR: Failed to update package lists."
    echo "Please check your internet connection and opkg configuration."
    echo "--------------------------------------------------"
    exit 1
fi

# Added 'procps-ng-pgrep' to ensure all process management tools are installed.
echo "Installing necessary packages (curl, openssh, sshpass, pkill, pgrep)..."
opkg install curl openssh-client openssh-client-utils sshpass procps-ng-pkill procps-ng-pgrep
if [ $? -ne 0 ]; then
    echo "--------------------------------------------------"
    echo "ERROR: Failed to install one or more packages."
    echo "Please check the opkg output above for specific error messages."
    echo "--------------------------------------------------"
    exit 1
fi

echo "Creating LuCI files..."
# Create necessary directories
mkdir -p /usr/lib/lua/luci/controller /usr/lib/lua/luci/model/cbi /usr/lib/lua/luci/view

# Create LuCI Controller
cat > /usr/lib/lua/luci/controller/sshplus.lua <<'EoL'
module("luci.controller.sshplus", package.seeall)
function index()
	if not nixio.fs.access("/etc/init.d/sshplus") then return end
	-- FIX: Changed menu path to /admin/peditxos/sshplus and set order to 10
	entry({"admin", "peditxos"}, firstchild(), "PeDitXOS Tools", 50).dependent=true
	entry({"admin", "peditxos", "sshplus"}, cbi("sshplus_manager"), "SSHPlus", 10).dependent = true
	entry({"admin", "peditxos", "sshplus_api"}, call("api_handler")).leaf = true
end
function api_handler()
	local action = luci.http.formvalue("action")
	if action == "status" then
		local running = (luci.sys.call("pgrep -f 'sshplus_service' >/dev/null 2>&1") == 0)
		local ip = "N/A"; local uptime = 0; local active_profile_id = luci.sys.exec("uci get sshplus.global.active_profile 2>/dev/null"):gsub("\n","")
		local active_profile_name = "None"
		if active_profile_id ~= "" then
			local user = luci.sys.exec("uci get sshplus." .. active_profile_id .. ".user 2>/dev/null"):gsub("\n","")
			local host = luci.sys.exec("uci get sshplus." .. active_profile_id .. ".host 2>/dev/null"):gsub("\n","")
			if user ~= "" and host ~= "" then active_profile_name = user .. "@" .. host else active_profile_name = active_profile_id end
		end
		if running then
			local f = io.open("/tmp/sshplus_start_time", "r")
			if f then local start_time = tonumber(f:read("*l") or "0"); f:close(); if start_time > 0 then uptime = os.time() - start_time end end
			local ip_handle = io.popen("curl --max-time 5 --socks5 127.0.0.1:8089 -s http://ifconfig.me/ip")
			ip = ip_handle:read("*a"):gsub("\n", ""); ip_handle:close()
			if ip == "" then ip = "Checking..." end
		end
		luci.http.prepare_content("application/json"); luci.http.write_json({running = running, ip = ip, uptime = uptime, profile = active_profile_name})
	elseif action == "toggle" then
		local is_running = (luci.sys.call("pgrep -f 'sshplus_service' >/dev/null 2>&1") == 0)
		if is_running then
			luci.sys.call("/etc/init.d/sshplus stop")
		else
			luci.sys.call("/etc/init.d/sshplus start")
		end
		luci.http.status(200, "OK")
	elseif action == "log" then
		local log_content = ""
		local f = io.open("/tmp/sshplus.log", "r")
		if f then log_content = f:read("*a"); f:close() end
		luci.http.prepare_content("application/json"); luci.http.write_json({log = log_content})
	elseif action == "clear_log" then
		luci.sys.call("echo 'Log cleared by user at $(date)' > /tmp/sshplus.log")
		luci.http.status(200, "OK")
	end
end
EoL

# Create LuCI Model (No changes)
cat > /usr/lib/lua/luci/model/cbi/sshplus_manager.lua <<'EoL'
local m = Map("sshplus", "SSHPlus Manager", "Manage status and profiles for your SSH tunnel.")
local s_status = m:section(SimpleSection, "Status & Control"); s_status.template = "sshplus_status_section"
local s_global = m:section(TypedSection, "sshplus", "Global Settings"); s_global.anonymous = true; s_global.addremove = false
local active_profile = s_global:option(ListValue, "active_profile", "Active Profile")
active_profile:value("", "-- Select Profile --")
m.uci:foreach("sshplus", "profile", function(s) active_profile:value(s[".name"], string.format("%s@%s", s.user or "user", s.host or "host")) end)
local s_profiles = m:section(TypedSection, "profile", "Connection Profiles"); s_profiles.anonymous = false; s_profiles.addremove = true; s_profiles.sortable = true
s_profiles:option(Value, "host", "SSH Host/IP"); s_profiles:option(Value, "user", "SSH Username"); s_profiles:option(Value, "port", "SSH Port", "Default is 22").placeholder = "22"
local auth = s_profiles:option(ListValue, "auth_method", "Auth Method"); auth:value("password", "Password"); auth:value("key", "Private Key")
local pass = s_profiles:option(Value, "pass", "SSH Password"); pass.password = true; pass:depends("auth_method", "password")
local keyfile = s_profiles:option(Value, "key_file", "Private Key Path"); keyfile:depends("auth_method", "key"); keyfile.placeholder = "/root/.ssh/id_rsa"
return m
EoL

# Create LuCI View
cat > /usr/lib/lua/luci/view/sshplus_status_section.htm <<'EoL'
<style>
.sshplus-main-container{width:95%;max-width:1200px;margin:20px auto;background:rgba(0,0,0,0.4);-webkit-backdrop-filter:blur(10px);backdrop-filter:blur(10px);border:1px solid rgba(255,255,255,0.1);border-radius:.75rem;padding:25px;box-shadow:0 8px 32px 0 rgba(0,0,0,0.37)}
.sshplus-layout{display:flex;gap:20px}
.sshplus-log-viewer{flex:1;background-color:#1e1e1e;color:#d4d4d4;font-family:monospace;font-size:0.85em;padding:15px;border-radius:5px;height:280px;overflow-y:scroll;white-space:pre-wrap;border:1px solid rgba(255,255,255,0.1)}
.sshplus-status-panel{flex:0 0 250px;color:#f0f0f0}
.sshplus-status-row{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px;font-size:1.05em}
.sshplus-status-label{color:#c0c0c0}
.sshplus-status-value{font-weight:700;color:#00b5e2;text-align:right}
.sshplus-status-state{font-weight:700;color:#38db8b}
.sshplus-status-state.disconnected{color:#ff4d4d}
.sshplus-actions{margin-top:20px;display:flex;gap:10px}
.sshplus-btn{flex:1;color:#fff;font-size:1.1em;border-radius:5px;padding:10px;border:none;cursor:pointer;font-weight:700;transition:background-color .3s}
.sshplus-btn.disconnect{background:#ff4d4d}
.sshplus-btn.connect{background:#38db8b}
.sshplus-btn:hover{opacity:0.9}
.sshplus-btn:disabled{opacity:0.5;cursor:not-allowed}
.sshplus-btn-clear{background-color:#555;padding:10px 15px}
</style>
<div class="sshplus-main-container">
	<div class="sshplus-layout">
        <!-- FIX: Swapped the position of status panel and log viewer -->
		<div class="sshplus-status-panel">
			<div class="sshplus-status-row"><span class="sshplus-status-label">Profile</span><span id="profileText" class="sshplus-status-value">-</span></div>
			<div class="sshplus-status-row"><span class="sshplus-status-label">Status</span><span id="statusText" class="sshplus-status-state">Checking...</span></div>
			<div class="sshplus-status-row"><span class="sshplus-status-label">IP</span><span id="ipText" class="sshplus-status-value">-</span></div>
			<div class="sshplus-status-row"><span class="sshplus-status-label">Uptime</span><span id="uptimeText" class="sshplus-status-value">-</span></div>
			<div class="sshplus-actions">
				<button class="sshplus-btn" id="mainBtn" onclick="toggleService()"></button>
				<button class="sshplus-btn sshplus-btn-clear" onclick="clearLog()" title="Clear Log">✖</button>
			</div>
		</div>
		<pre id="logViewer" class="sshplus-log-viewer">Loading log...</pre>
	</div>
</div>
<script>
var logPollInterval;
function formatUptime(s){if(isNaN(s)||s<=0)return"-";let h=Math.floor(s/3600);s%=3600;let m=Math.floor(s/60);s=Math.floor(s%60);let t=[];if(h>0){t.push(h+"h")}if(m>0){t.push(m+"m")}if(s>0||t.length===0){t.push(s+"s")}return t.join(" ")}
function updateStatus(){XHR.get('<%=luci.dispatcher.build_url("admin/peditxos/sshplus_api")%>?action=status',null,function(x,st){if(!st)return;let r=st.running,ip=st.ip?.trim()||"N/A",up=st.uptime||0,p=st.profile||"None";let s=document.getElementById("statusText");s.innerHTML=r?"Connected":"Disconnected";s.className="sshplus-status-state"+(r?"":" disconnected");document.getElementById("ipText").innerText=ip;document.getElementById("uptimeText").innerText=formatUptime(up);document.getElementById("profileText").innerText=p;let b=document.getElementById("mainBtn");b.className="sshplus-btn"+(r?" disconnect":" connect");b.innerText=r?"Disconnect":"Connect"})}
function pollLog(){XHR.get('<%=luci.dispatcher.build_url("admin/peditxos/sshplus_api")%>?action=log',null,function(x,st){if(!st)return;var v=document.getElementById("logViewer");var isScrolledBottom=v.scrollHeight-v.clientHeight<=v.scrollTop+5;var logText=st.log||"Log is empty.";if(v.textContent!==logText){v.textContent=logText;if(isScrolledBottom){v.scrollTop=v.scrollHeight}}})}
function toggleService(){var b=document.getElementById("mainBtn");b.disabled=true;XHR.get('<%=luci.dispatcher.build_url("admin/peditxos/sshplus_api")%>?action=toggle',null,function(){setTimeout(function(){updateStatus();pollLog();b.disabled=false},2000)})}
function clearLog(){XHR.get('<%=luci.dispatcher.build_url("admin/peditxos/sshplus_api")%>?action=clear_log',null,function(){pollLog()})}
function startPolling(){if(!logPollInterval){logPollInterval=setInterval(function(){updateStatus();pollLog()},2500)}updateStatus();pollLog()}
window.addEventListener('load',startPolling);
</script>
EoL

echo "Creating service files..."
# Create init.d service script (No changes)
cat > /etc/init.d/sshplus <<'EoL'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1
LOG_FILE="/tmp/sshplus.log"

start_service() {
	echo "--- SSHPlus Service Starting at $(date) ---" > $LOG_FILE
	procd_open_instance
	procd_set_param command /bin/sh -c "/usr/bin/sshplus_service >> $LOG_FILE 2>&1"
	procd_set_param respawn
	procd_close_instance
}

stop_service() {
	echo "--- SSHPlus Service Stopping at $(date) ---" >> $LOG_FILE
	pkill -f "/usr/bin/sshplus_service"
	pkill -f "sshpass -p .* /usr/bin/ssh .*-D 127.0.0.1:8089"
	rm -f /tmp/sshplus_start_time
	echo "--- SSHPlus Service Stopped ---" >> $LOG_FILE
}
EoL
chmod +x /etc/init.d/sshplus

# Create the main service binary (No changes)
cat > /usr/bin/sshplus_service <<'EoL'
#!/bin/sh
# All output from this script will be redirected to the log file by the init.d script.

# The script will check if stdbuf exists and use it if available.
# No installation is attempted anymore.
STDBUF_CMD=""
if [ -x /usr/bin/stdbuf ]; then
	STDBUF_CMD="/usr/bin/stdbuf -o0"
fi

# Define the full path to the openssh client
SSH_BIN="/usr/bin/ssh"

if [ ! -x "$SSH_BIN" ]; then
    echo "FATAL ERROR: OpenSSH client not found at $SSH_BIN."
    echo "Please install it with: opkg install openssh-client"
    sleep 300 # Sleep to avoid rapid respawn loops
    exit 1
fi

while true; do
	ACTIVE_PROFILE=$(uci get sshplus.global.active_profile 2>/dev/null)
	if [ -z "$ACTIVE_PROFILE" ]; then
		echo "ERROR: No active SSHPlus profile is selected."
		echo "Please select a profile in LuCI and save. Sleeping for 60s..."
		sleep 60
		continue
	fi
	
	echo "Reading configuration for profile: $ACTIVE_PROFILE"
	HOST=$(uci get sshplus.$ACTIVE_PROFILE.host)
	USER=$(uci get sshplus.$ACTIVE_PROFILE.user)
	PORT=$(uci get sshplus.$ACTIVE_PROFILE.port)
	AUTH_METHOD=$(uci get sshplus.$ACTIVE_PROFILE.auth_method)
	PASS=$(uci get sshplus.$ACTIVE_PROFILE.pass)
	KEY_FILE=$(uci get sshplus.$ACTIVE_PROFILE.key_file)
	
	if [ -z "$HOST" ] || [ -z "$USER" ] || [ -z "$PORT" ]; then
		echo "ERROR: Profile '$ACTIVE_PROFILE' is not fully configured."
		echo "Sleeping for 60s..."
		sleep 60
		continue
	fi
	
	echo "Configuration loaded. Preparing to connect using OpenSSH..."
	date +%s > /tmp/sshplus_start_time
	
	# These options are for OpenSSH and will now work correctly.
	SSH_CMD_OPTIONS="-v -T -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o ExitOnForwardFailure=yes -D 127.0.0.1:8089 -N -p $PORT $USER@$HOST"
	
	echo "Executing SSH command..."
	
	if [ "$AUTH_METHOD" = "key" ]; then
		echo "Authentication Method: Private Key ($KEY_FILE)"
		$STDBUF_CMD $SSH_BIN -i "$KEY_FILE" $SSH_CMD_OPTIONS
	else
		echo "Authentication Method: Password"
		$STDBUF_CMD sshpass -p "$PASS" $SSH_BIN $SSH_CMD_OPTIONS
	fi
	
	echo "SSH tunnel disconnected. Exit code: $?. Reconnecting in 5s..."
	rm -f /tmp/sshplus_start_time
	sleep 5
done
EoL
chmod +x /usr/bin/sshplus_service

# Replaced with the new, more detailed Passwall configuration logic.
echo "Configuring Passwall/Passwall2 if present..."
if service passwall2 status > /dev/null 2>&1; then
    uci set passwall2.SshPlus=nodes
    uci set passwall2.SshPlus.remarks='ssh-plus'
    uci set passwall2.SshPlus.type='Xray'
    uci set passwall2.SshPlus.protocol='socks'
    uci set passwall2.SshPlus.server='127.0.0.1'
    uci set passwall2.SshPlus.port='8089'
    uci set passwall2.SshPlus.address='127.0.0.1'
    uci set passwall2.SshPlus.tls='0'
    uci set passwall2.SshPlus.transport='tcp'
    uci set passwall2.SshPlus.tcp_guise='none'
    uci set passwall2.SshPlus.tcpMptcp='0'
    uci set passwall2.SshPlus.tcpNoDelay='0'
    uci commit passwall2
    echo "Passwall2 configuration updated successfully."
elif service passwall status > /dev/null 2>&1; then
    uci set passwall.SshPlus=nodes
    uci set passwall.SshPlus.remarks='Ssh-Plus'
    uci set passwall.SshPlus.type='Xray'
    uci set passwall.SshPlus.protocol='socks'
    uci set passwall.SshPlus.server='127.0.0.1'
    uci set passwall.SshPlus.port='8089'
    uci set passwall.SshPlus.address='127.0.0.1'
    uci set passwall.SshPlus.tls='0'
    uci set passwall.SshPlus.transport='tcp'
    uci set passwall.SshPlus.tcp_guise='none'
    uci set passwall.SshPlus.tcpMptcp='0'
    uci set passwall.SshPlus.tcpNoDelay='0'
    uci commit passwall
    echo "Passwall configuration updated successfully."
else
    echo "Neither Passwall nor Passwall2 is installed. Skipping configuration."
fi


# Service is now enabled and restarted at the end, after all files are created.
echo "Enabling and restarting the service..."
/etc/init.d/sshplus enable
/etc/init.d/sshplus restart

echo ">>> SSHPlus installation/update complete."

# FIX: Added final ASCII art banner
cat << "EoL"
  ______     _____  _   _   _   _____      
 (_____ \   (____ \(_)_  \ \ / /   / ___ \     
  _____) )___ _   \ \ _| |_  \ \/ /   | |   | | ___ 
 |  ____/ _  ) |   | | |  _)  )  (    | |   | |/___)
 | |   ( (/ /| |__/ /| | |__ / /\ \   | |___| |___ |
 |_|    \____)_____/ |_|\___)_/  \_\   \_____/(___/ 
                                                  
                                       SSHPlus by PeDitX
EoL
