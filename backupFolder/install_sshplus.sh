#!/bin/sh

# ==========================================
# PeDitXOS Tools - SSHPlus Installer (v16)
# ==========================================
# Targets: OpenWrt 21.02 / 22.03 / 23.05 / 24.10 (opkg)
#          OpenWrt 25.12+              (apk)
# Layout follows the "peditxos-app-maker" skill:
#   - dual package manager (PKG / PKG_UPDATE / PKG_INSTALL)
#   - JSON-RPC style endpoints returning { success, data|output }
#   - rpcd ACL
#   - /usr/bin/sshplus           (terminal CLI, plain POSIX sh)
#   - /usr/bin/sshplus-backend.sh  +  crontab
#   - Vanilla JS view with Light/Dark theme + localStorage
# ==========================================

echo ">>> Starting SSHPlus Installation (v16 - opkg + apk) ..."

# ------------------------------------------
# 1. PACKAGE MANAGER DETECTION
# ------------------------------------------
if command -v apk >/dev/null 2>&1; then
	PKG="apk"
	PKG_UPDATE="apk update"
	PKG_INSTALL="apk add --no-cache"
elif command -v opkg >/dev/null 2>&1; then
	PKG="opkg"
	PKG_UPDATE="opkg update"
	PKG_INSTALL="opkg install"
else
	echo "ERROR: No supported package manager found (need apk or opkg)"
	exit 1
fi
echo "INFO: using package manager: $PKG"

# ------------------------------------------
# 2. HELPERS
# ------------------------------------------
log_info()    { echo "INFO: $1"; }
log_success() { echo "SUCCESS: $1"; }
log_warn()    { echo "WARN: $1"; }
log_error()   { echo "ERROR: $1"; }

APP_NAME="sshplus"
APP_TITLE="SSHPlus"
UCI_CFG="sshplus"
SVC="/etc/init.d/sshplus"
KNOWN_HOSTS="/root/.ssh/sshplus_known_hosts"

# Lua runtime packages. Required on 25.12 (luci-base no longer ships Lua),
# already present / not yet split out on older releases -> installed best effort.
DEPS_LUCI="luci-base rpcd rpcd-mod-luci luci-lua-runtime luci-compat"
DEPS_SSH="curl openssh-client openssh-client-utils sshpass procps-ng-pgrep procps-ng-pkill"

# ------------------------------------------
# 3. DEPENDENCIES
# ------------------------------------------
log_info "Updating package lists..."
if ! $PKG_UPDATE >/dev/null 2>&1; then
	log_warn "$PKG_UPDATE failed - continuing with cached lists."
fi

if $PKG_INSTALL $DEPS_LUCI $DEPS_SSH >/dev/null 2>&1; then
	log_success "Dependencies installed."
else
	log_warn "Full dependency set failed; retrying without luci-lua-runtime / luci-compat."
	if $PKG_INSTALL luci-base rpcd rpcd-mod-luci $DEPS_SSH >/dev/null 2>&1; then
		log_success "Dependencies installed (legacy layout)."
	else
		log_error "Failed to install dependencies."
		echo "       Tried: $DEPS_LUCI $DEPS_SSH"
		exit 1
	fi
fi

# curl repair ---------------------------------------------------------------
# SSHPlus v15 shipped an `opkg remove curl ...` line in its uninstaller, which
# silently broke luci-app-passwall2: its connect_status() controller does
#   local use_time = luci.sys.exec("... curl ...")
# and then arithmetic on it, so a missing curl turns every "connectivity
# check" into HTTP 500 / "attempt to perform arithmetic on local 'use_time'".
# curl is also how SSHPlus resolves the egress IP. Never leave it missing.
if ! command -v curl >/dev/null 2>&1; then
	log_warn "curl is missing (PassWall2's connectivity check and the egress IP need it)."
	$PKG_INSTALL curl >/dev/null 2>&1 || true
	if command -v curl >/dev/null 2>&1; then
		log_success "curl restored."
	else
		log_warn "Could not install curl automatically - run: apk add curl  |  opkg install curl"
	fi
fi

# Sanity check: the controller/view are Lua, they need the Lua runtime.
if [ ! -f /usr/lib/lua/luci/dispatcher.lua ]; then
	log_warn "LuCI Lua runtime not found (/usr/lib/lua/luci/dispatcher.lua)."
	log_warn "Package 'luci-lua-runtime' is required on OpenWrt 24.10 / 25.12."
	log_warn "Install it manually if the PeDitXOS Tools menu does not appear."
fi
if [ ! -f /usr/lib/lua/luci/cbi.lua ]; then
	log_warn "LuCI CBI not found - package 'luci-compat' is missing."
fi

# ------------------------------------------
# 4. UCI CONFIG (created if missing, preserved otherwise)
# ------------------------------------------
if [ ! -f "/etc/config/${UCI_CFG}" ]; then
	log_info "Creating configuration file..."
	cat > "/etc/config/${UCI_CFG}" <<'EoL'
config sshplus 'global'
	option enabled '1'
	option active_profile ''
	option socks_port '8089'

config profile
	option host 'host.example.com'
	option user 'root'
	option port '22'
	option auth_method 'password'
	option pass ''
	option key_file '/root/.ssh/id_rsa'
EoL
else
	log_info "Existing configuration kept."
	# Migrate pre-v16 configs (missing options)
	uci -q get "${UCI_CFG}.global.enabled" >/dev/null 2>&1 || uci -q set "${UCI_CFG}.global.enabled='1'"
	uci -q get "${UCI_CFG}.global.socks_port" >/dev/null 2>&1 || uci -q set "${UCI_CFG}.global.socks_port='8089'"
	uci -q commit "${UCI_CFG}"
fi

# ------------------------------------------
# 5. CONTROLLER (JSON-RPC ENDPOINTS)
# ------------------------------------------
log_info "Creating LuCI files..."
mkdir -p /usr/lib/lua/luci/controller /usr/lib/lua/luci/model/cbi /usr/lib/lua/luci/view/sshplus

cat > "/usr/lib/lua/luci/controller/${APP_NAME}.lua" <<'LUAEOF'
module("luci.controller.sshplus", package.seeall)

local http  = require "luci.http"
local jsonc = require "luci.jsonc"
local sys   = require "luci.sys"
local fs    = require "nixio.fs"
local uci   = require "luci.model.uci".cursor()

local CFG    = "sshplus"
local SVC    = "/etc/init.d/sshplus"
local STATUS = "/tmp/sshplus-status.json"
local LOGF   = "/tmp/sshplus.log"
local IPF    = "/tmp/sshplus-ip.txt"
local BACK   = "/usr/bin/sshplus-backend.sh"
local PW     = { "passwall2", "passwall" }

-- keys accepted by action_save (everything else is rejected)
local SAVE_KEYS = { enabled = 1, active_profile = 1, socks_port = 1 }

local function json_resp(t)
	http.prepare_content("application/json")
	http.write_json(t)
end

local function trim(s)
	return (tostring(s or ""):gsub("%s+$", ""):gsub("^%s+", ""))
end

local function valid_id(s)
	return type(s) == "string" and s:match("^[%w_%-]+$") ~= nil
end

local function is_running()
	return (sys.call("pgrep -f 'sshplus_service' >/dev/null 2>&1") == 0)
end

local function get(opt, default)
	local v = uci:get(CFG, "global", opt)
	v = trim(v)
	if v == "" then return default or "" end
	return v
end

-- passwall / passwall2 node state -------------------------------------
local function passwall_state()
	for _, c in ipairs(PW) do
		if fs.access("/etc/config/" .. c) then
			local node = trim(sys.exec("uci -q get " .. c .. ".SshPlus 2>/dev/null"))
			return c, (node ~= "" and node == "nodes")
		end
	end
	return "none", false
end

local function profile_label(pid)
	if pid == "" then return "None" end
	local user = trim(uci:get(CFG, pid, "user"))
	local host = trim(uci:get(CFG, pid, "host"))
	if user ~= "" and host ~= "" then
		return user .. "@" .. host
	end
	return pid
end

-- =========================================
-- MENU  (PeDitXOS Tools -> SSHPlus)
-- =========================================
function index()
	if not fs.access(SVC) then return end

	entry({"admin", "peditxos"}, firstchild(), "PeDitXOS Tools", 40).dependent = true

	-- luci-theme-peditx draws the tab bar from the CHILDREN of the node at
	-- depth 3 (menu-peditx.js: renderTabMenu), not from sibling entries.
	-- So SSHPlus has to be a parent node holding the real pages - two sibling
	-- entries would simply render no tabs at all.
	entry({"admin", "peditxos", "sshplus"}, firstchild(), "SSHPlus", 10).dependent = true
	entry({"admin", "peditxos", "sshplus", "status"},   cbi("sshplus_manager"),  "Status",  10)
	entry({"admin", "peditxos", "sshplus", "profiles"}, cbi("sshplus_profiles"), "Profiles", 20)

	-- JSON-RPC style endpoints:
	--   /cgi-bin/luci/admin/peditxos/sshplus_api/{status,save,run,test,live,toggle,log,clear_log}
	-- Mounted under "admin/" (not "/rpc/") so it inherits the LuCI session auth.
	entry({"admin", "peditxos", "sshplus_api"}, call("api_dispatch")).leaf = true
end

-- =========================================
-- ENDPOINT: status  (read only)
-- =========================================
function action_status()
	local enabled  = get("enabled", "1")
	local sport    = get("socks_port", "8089")
	local pid      = get("active_profile", "")
	local running  = is_running()
	local uptime   = 0

	if running then
		local f = io.open("/tmp/sshplus_start_time", "r")
		if f then
			local t = tonumber(f:read("*l") or "0") or 0
			f:close()
			if t > 0 then uptime = os.time() - t end
		end
	end

	local ip = "N/A"
	local f = io.open(IPF, "r")
	if f then ip = trim(f:read("*a")); f:close() end
	if ip == "" then ip = (running and "checking..." or "N/A") end

	local pw, pw_node = passwall_state()

	json_resp({
		success = true,
		data = {
			running       = running,
			enabled       = enabled,
			uptime        = uptime,
			ip            = ip,
			socks_port    = sport,
			profile       = pid,
			profile_name  = profile_label(pid),
			passwall      = pw,
			passwall_node = pw_node,
		}
	})
end

-- =========================================
-- ENDPOINT: save  (global settings only)
-- =========================================
function action_save()
	local data = jsonc.parse(http.content() or "")
	if type(data) ~= "table" then
		json_resp({ success = false, message = "Invalid JSON" })
		return
	end

	for k, v in pairs(data) do
		if not SAVE_KEYS[k] then
			json_resp({ success = false, message = "Rejected key: " .. tostring(k) })
			return
		end

		if k == "socks_port" then
			local n = tonumber(tostring(v):match("(%d+)"))
			if not n or n < 1 or n > 65535 then
				json_resp({ success = false, message = "Invalid port" })
				return
			end
			v = tostring(n)
		elseif k == "enabled" then
			v = (tostring(v) == "1" or tostring(v) == "true") and "1" or "0"
		elseif k == "active_profile" then
			v = tostring(v)
			if v ~= "" and not valid_id(v) then
				json_resp({ success = false, message = "Invalid profile id" })
				return
			end
			if v ~= "" and not uci:get(CFG, v) then
				json_resp({ success = false, message = "Profile not found" })
				return
			end
		end

		uci:set(CFG, "global", k, v)
	end
	uci:commit(CFG)

	-- keep the passwall node in sync with socks_port
	sys.call(BACK .. " passwall_sync >/dev/null 2>&1")

	local enabled = get("enabled", "1")
	if enabled == "1" then
		sys.call(SVC .. " restart >/dev/null 2>&1")
	else
		sys.call(SVC .. " stop >/dev/null 2>&1")
	end

	json_resp({ success = true, data = { enabled = enabled } })
end

-- =========================================
-- ENDPOINT: run  (backend action)
-- =========================================
function action_run()
	local data = jsonc.parse(http.content() or "") or {}
	local arg_str = tostring(data.arg or "")
	-- security: allow only [A-Za-z0-9._-] - block shell injection
	if arg_str ~= "" and arg_str:find("[^%w%-_%.]") then
		json_resp({ success = false, message = "Invalid arg" })
		return
	end
	local out = sys.exec(BACK .. " run " .. arg_str .. " 2>&1")
	json_resp({ success = true, output = out })
end

-- =========================================
-- ENDPOINT: test  (end to end SSH probe)
-- =========================================
function action_test()
	local out = sys.exec(BACK .. " test 2>&1")
	local ok = (out:find("SSHPLUS_TEST_OK", 1, true) ~= nil)
	json_resp({ success = ok, output = out })
end

-- =========================================
-- ENDPOINT: live  (realtime sync, 5s polling)
-- =========================================
function action_live()
	local raw = sys.exec("cat " .. STATUS .. " 2>/dev/null || true")
	local ok, data = pcall(jsonc.parse, raw)
	json_resp({ success = true, data = (ok and type(data) == "table" and data) or { status = "unknown" } })
end

-- =========================================
-- ENDPOINT: toggle  (connect / disconnect)
-- =========================================
function action_toggle()
	if is_running() then
		sys.call(SVC .. " stop >/dev/null 2>&1")
		json_resp({ success = true, data = { running = false } })
	else
		uci:set(CFG, "global", "enabled", "1")
		uci:commit(CFG)
		sys.call(SVC .. " start >/dev/null 2>&1")
		json_resp({ success = true, data = { running = true } })
	end
end

-- =========================================
-- ENDPOINT: log / clear_log
-- =========================================
function action_log()
	local c = ""
	local f = io.open(LOGF, "r")
	if f then c = f:read("*a") or ""; f:close() end
	if #c > 65536 then c = "... (truncated)\n" .. c:sub(-65536) end
	json_resp({ success = true, data = { log = c } })
end

function action_clear_log()
	sys.call('echo "Log cleared at $(date)" > ' .. LOGF)
	json_resp({ success = true, data = { log = "Log cleared." } })
end

-- =========================================
-- DISPATCH  (path segment OR legacy ?action=)
-- =========================================
local ACTIONS = {
	status   = action_status,
	save     = action_save,
	run      = action_run,
	test     = action_test,
	live     = action_live,
	toggle   = action_toggle,
	log      = action_log,
	clear_log = action_clear_log,
}

function api_dispatch(action)
	action = action or http.formvalue("action") or "status"
	local fn = ACTIONS[action]
	if not fn then
		json_resp({ success = false, message = "Unknown action: " .. tostring(action) })
		return
	end
	fn()
end
LUAEOF
log_success "Controller created."

# ------------------------------------------
# 6. FRONTEND VIEW (Vanilla JS + Dual Theme)
# ------------------------------------------
cat > "/usr/lib/lua/luci/view/${APP_NAME}/main.htm" <<'HTMLEOF'
<style>
/* ===== DARK THEME (default) ===== */
:root, [data-theme="dark"] {
	--p:#00d4aa; --p2:#00b894; --bg:#1a1d23; --card:#23272f;
	--border:#333; --text:#e4e7ec; --muted:#889; --input-bg:#1a1d23;
	--danger:#ff5050; --warn:#f1fa8c; --log-bg:#0d1117; --log-text:#c9d1d9;
	--header-bg:#181b20; --shadow:rgba(0,0,0,.3);
	--switch-bg:#555; --switch-knob:#fff;
	--msg-ok-bg:rgba(0,212,170,.15); --msg-ok-border:#00d4aa;
	--msg-err-bg:rgba(255,80,80,.15); --msg-err-border:#ff5050;
}
/* ===== LIGHT THEME ===== */
[data-theme="light"] {
	--p:#00897b; --p2:#00695c; --bg:#f0f2f5; --card:#ffffff;
	--border:#ddd; --text:#1a1a2e; --muted:#666; --input-bg:#f8f9fa;
	--danger:#d32f2f; --warn:#f9a825; --log-bg:#f5f5f5; --log-text:#333;
	--header-bg:#fff; --shadow:rgba(0,0,0,.08);
	--switch-bg:#ccc; --switch-knob:#fff;
	--msg-ok-bg:rgba(0,137,123,.1); --msg-ok-border:#00897b;
	--msg-err-bg:rgba(211,47,47,.1); --msg-err-border:#d32f2f;
}

.sshplus-app {
	color: var(--text);
	background: var(--bg);
	border: 1px solid var(--border);
	border-radius: 12px;
	padding: 20px;
	margin-bottom: 16px;
	box-shadow: 0 2px 8px var(--shadow);
	transition: background .3s, border-color .3s, color .3s;
}
.sshplus-app .card {
	background: var(--card); border: 1px solid var(--border);
	border-radius: 12px; padding: 20px; margin-bottom: 16px;
	transition: background .3s, border-color .3s, color .3s;
}
.sshplus-app .card:last-child { margin-bottom: 0; }
.sshplus-app .card h3 { color: var(--p); margin: 0 0 16px; font-size: 1.05rem; }

/* Theme switch */
.sshplus-head {
	display: flex; align-items: center; justify-content: space-between;
	gap: 12px; margin-bottom: 16px; flex-wrap: wrap;
}
.sshplus-head h3 { margin: 0; }
.sshplus-plink {
	display: inline-flex; align-items: center; gap: 6px;
	color: var(--muted); text-decoration: none;
	background: var(--card); border: 1px solid var(--border);
	border-radius: 20px; padding: 6px 12px; font-size: .85rem;
	box-shadow: 0 2px 8px var(--shadow);
	transition: color .2s, border-color .2s;
	white-space: nowrap;
}
.sshplus-plink:hover { color: var(--p); border-color: var(--p); }
.sshplus-theme {
	display: inline-flex; align-items: center; gap: 8px;
	background: var(--card); border: 1px solid var(--border);
	border-radius: 20px; padding: 4px 12px; font-size: .85rem;
	box-shadow: 0 2px 8px var(--shadow);
}
.sshplus-theme input[type="checkbox"] {
	width: 36px; height: 20px; appearance: none; -webkit-appearance: none;
	background: var(--switch-bg); border-radius: 10px; position: relative;
	cursor: pointer; transition: background .3s; outline: none; border: none; margin: 0;
}
.sshplus-theme input[type="checkbox"]::after {
	content: ''; position: absolute; top: 2px; left: 2px;
	width: 16px; height: 16px; border-radius: 50%;
	background: var(--switch-knob); transition: transform .3s;
}
.sshplus-theme input[type="checkbox"]:checked { background: var(--p); }
.sshplus-theme input[type="checkbox"]:checked::after { transform: translateX(16px); }

/* Buttons */
.sshplus-app .btn {
	background: var(--p); color: #fff; border: none;
	padding: 10px 20px; border-radius: 8px; font-weight: 600;
	cursor: pointer; transition: opacity .2s; margin: 0 8px 8px 0;
}
.sshplus-app .btn:hover { opacity: .85; }
.sshplus-app .btn:disabled { opacity: .4; cursor: not-allowed; }
.sshplus-app .btn-secondary { background: var(--switch-bg); color: var(--text); }
.sshplus-app .btn-danger { background: var(--danger); color: #fff; }

/* Inputs */
.sshplus-app .input {
	width: 100%; padding: 10px; border: 1px solid var(--border);
	background: var(--input-bg); color: var(--text);
	border-radius: 8px; box-sizing: border-box; margin-bottom: 12px;
	transition: background .3s, color .3s;
}
.sshplus-app .input:focus { outline: none; border-color: var(--p); }

/* Messages */
.sshplus-app .msg {
	padding: 12px; border-radius: 8px; margin: 12px 0;
	font-family: monospace; font-size: .9rem; display: none;
}
.sshplus-app .msg.ok { display: block; background: var(--msg-ok-bg); border: 1px solid var(--msg-ok-border); }
.sshplus-app .msg.err { display: block; background: var(--msg-err-bg); border: 1px solid var(--msg-err-border); }

/* Log boxes */
.sshplus-app .log-box {
	background: var(--log-bg); color: var(--log-text);
	border: 1px solid var(--border); border-radius: 8px;
	padding: 16px; max-height: 300px; overflow: auto;
	font-family: monospace; font-size: .85rem; white-space: pre-wrap;
	transition: background .3s, color .3s; margin: 0;
}

/* Status rows */
.sshplus-row {
	display: flex; justify-content: space-between; align-items: center;
	margin-bottom: 10px; font-size: .95rem; gap: 12px;
}
.sshplus-row .k { color: var(--muted); }
.sshplus-row .v { font-weight: 700; color: var(--p); text-align: right; word-break: break-all; }

/* Toggle */
.sshplus-app .toggle { display: flex; align-items: center; gap: 10px; cursor: pointer; }
.sshplus-app .toggle input { width: 40px; height: 22px; appearance: none; -webkit-appearance: none;
	background: var(--switch-bg); border-radius: 11px; position: relative; cursor: pointer;
	transition: background .3s; outline: none; border: none; margin: 0; }
.sshplus-app .toggle input::after { content: ''; position: absolute; top: 2px; left: 2px;
	width: 18px; height: 18px; border-radius: 50%; background: var(--switch-knob); transition: transform .3s; }
.sshplus-app .toggle input:checked { background: var(--p); }
.sshplus-app .toggle input:checked::after { transform: translateX(18px); }

/* Badge */
.sshplus-app .badge {
	display: inline-block; padding: 2px 8px; border-radius: 10px;
	font-size: .75rem; font-weight: 600; margin-left: 8px;
	background: var(--switch-bg); color: var(--text);
}
.sshplus-app .badge.ok { background: var(--msg-ok-bg); color: var(--p); }
.sshplus-app .badge.err { background: var(--msg-err-bg); color: var(--danger); }
.sshplus-app .muted { color: var(--muted); font-size: .85rem; }
.sshplus-actions { margin-top: 14px; }
</style>

<div class="sshplus-app" id="sshplus-app" data-theme="dark">
	<div class="card">
		<div class="sshplus-head">
			<h3>⚙️ SSHPlus <span id="sp-badge" class="badge">…</span></h3>
			<a class="sshplus-plink" id="sp-profiles"
			   href="<%=luci.dispatcher.build_url("admin", "peditxos", "sshplus", "profiles")%>">👥 Profiles</a>
			<label class="sshplus-theme">
				<span>☀️</span>
				<input type="checkbox" id="sp-theme" title="Toggle Light/Dark theme">
				<span>🌙</span>
			</label>
		</div>

		<div class="sshplus-row"><span class="k">Active profile</span><span class="v" id="sp-profile">-</span></div>
		<div class="sshplus-row"><span class="k">SOCKS5 proxy</span><span class="v" id="sp-port">-</span></div>
		<div class="sshplus-row"><span class="k">Exit IP</span><span class="v" id="sp-ip">-</span></div>
		<div class="sshplus-row"><span class="k">Uptime</span><span class="v" id="sp-uptime">-</span></div>
		<div class="sshplus-row"><span class="k">PassWall node</span><span class="v" id="sp-pw">-</span></div>

		<label class="toggle">
			<input type="checkbox" id="sp-enabled">
			<span>Enable service</span>
		</label>

		<div class="sshplus-actions">
			<button type="button" class="btn" id="sp-toggle">🔌 Connect</button>
			<button type="button" class="btn btn-secondary" id="sp-test">🧪 Test</button>
			<button type="button" class="btn" id="sp-save">💾 Save &amp; Apply</button>
			<button type="button" class="btn btn-danger" id="sp-clear">🗑 Clear log</button>
		</div>
		<div id="sp-msg" class="msg"></div>
	</div>

	<div class="card">
		<h3>📊 Live Status</h3>
		<pre id="sp-live" class="log-box">Loading...</pre>
	</div>

	<div class="card">
		<h3>📋 Log</h3>
		<pre id="sp-log" class="log-box">Waiting for action...</pre>
	</div>
</div>

<script>
(function(){
	var API = '<%=luci.dispatcher.build_url("admin/peditxos/sshplus_api")%>';
	var app = document.getElementById('sshplus-app');

	/* ===== Theme toggle (scoped to the app, persisted) ===== */
	var tg = document.getElementById('sp-theme');
	var KEY = 'sshplus_theme';
	function applyTheme(t){
		app.setAttribute('data-theme', t);
		tg.checked = (t === 'light');
	}
	applyTheme(localStorage.getItem(KEY) || 'dark');
	tg.addEventListener('change', function(){
		var t = this.checked ? 'light' : 'dark';
		applyTheme(t);
		try { localStorage.setItem(KEY, t); } catch(e){}
	});

	/* ===== Helpers ===== */
	function showMsg(text, isErr){
		var el = document.getElementById('sp-msg');
		el.textContent = text;
		el.className = 'msg ' + (isErr ? 'err' : 'ok');
		setTimeout(function(){ el.className = 'msg'; }, 5000);
	}
	function showBadge(text, isErr){
		var el = document.getElementById('sp-badge');
		el.textContent = text;
		el.className = 'badge ' + (isErr ? 'err' : 'ok');
	}
	function fmtUptime(s){
		if (!s || s <= 0) return '-';
		var h = Math.floor(s/3600), m = Math.floor((s%3600)/60), sec = s%60, t = [];
		if (h > 0) t.push(h + 'h');
		if (m > 0) t.push(m + 'm');
		if (sec > 0 || t.length === 0) t.push(sec + 's');
		return t.join(' ');
	}
	function rpc(action, data){
		return fetch(API + '/' + action, {
			method: data ? 'POST' : 'GET',
			credentials: 'same-origin',
			headers: { 'Content-Type': 'application/json' },
			body: data ? JSON.stringify(data) : undefined
		}).then(function(r){ return r.json(); });
	}

	/* ===== Status ===== */
	function refreshStatus(){
		return rpc('status').then(function(res){
			if (!res || !res.success || !res.data) return;
			var d = res.data;
			document.getElementById('sp-profile').textContent = d.profile_name || 'None';
			document.getElementById('sp-port').textContent     = '127.0.0.1:' + (d.socks_port || '8089');
			document.getElementById('sp-ip').textContent       = d.ip || 'N/A';
			document.getElementById('sp-uptime').textContent   = fmtUptime(d.uptime);
			document.getElementById('sp-pw').textContent       =
				(d.passwall === 'none') ? 'not installed'
					: d.passwall + (d.passwall_node ? ' (Ssh-Plus node ✓)' : ' (node missing)');
			document.getElementById('sp-enabled').checked = (d.enabled === '1' || d.enabled === 'true');

			var b = document.getElementById('sp-toggle');
			b.textContent = d.running ? '⏹ Disconnect' : '🔌 Connect';

			showBadge(d.running ? 'Connected' : (d.enabled === '1' ? 'Disconnected' : 'Disabled'),
			          d.running ? false : true);
		}).catch(function(){ showBadge('Offline', true); });
	}

	/* ===== Live status ===== */
	function refreshLive(){
		return rpc('live').then(function(res){
			if (res && res.success && res.data){
				document.getElementById('sp-live').textContent = JSON.stringify(res.data, null, 2);
			}
		}).catch(function(){});
	}

	/* ===== Log ===== */
	function refreshLog(){
		return rpc('log').then(function(res){
			if (res && res.success && res.data){
				var v = document.getElementById('sp-log');
				var atBottom = (v.scrollHeight - v.clientHeight) <= (v.scrollTop + 5);
				var txt = res.data.log || 'Log is empty.';
				if (v.textContent !== txt){
					v.textContent = txt;
					if (atBottom) v.scrollTop = v.scrollHeight;
				}
			}
		}).catch(function(){});
	}

	/* ===== Actions ===== */
	document.getElementById('sp-toggle').onclick = function(){
		var b = this; b.disabled = true;
		rpc('toggle').then(function(){
			return refreshStatus();
		}).then(function(){
			b.disabled = false; refreshLog();
		}).catch(function(){ b.disabled = false; showMsg('Toggle failed', true); });
	};

	document.getElementById('sp-test').onclick = function(){
		var b = this; b.disabled = true; showMsg('Testing...', false);
		rpc('test', {}).then(function(res){
			b.disabled = false;
			document.getElementById('sp-log').textContent = (res && res.output) || '';
			if (res && res.success) showMsg('Connection test OK', false);
			else showMsg('Connection test FAILED', true);
		}).catch(function(e){ b.disabled = false; showMsg(String(e && e.message || e), true); });
	};

	document.getElementById('sp-save').onclick = function(){
		var b = this; b.disabled = true;
		var payload = {
			enabled: document.getElementById('sp-enabled').checked ? '1' : '0'
		};
		rpc('save', payload).then(function(res){
			b.disabled = false;
			if (res && res.success){ showMsg('Saved & applied', false); refreshStatus(); refreshLog(); }
			else showMsg((res && res.message) || 'Save failed', true);
		}).catch(function(e){ b.disabled = false; showMsg(String(e && e.message || e), true); });
	};

	document.getElementById('sp-clear').onclick = function(){
		rpc('clear_log', {}).then(function(){ refreshLog(); })
			.catch(function(){ showMsg('Clear failed', true); });
	};

	/* ===== Polling =====
	 * The refreshers are registered with LuCI's own poll loop
	 * (L.poll.add(fn, seconds)) instead of plain setInterval().
	 *
	 * LuCI's loop dispatches the `poll-start` / `poll-stop` document
	 * events, and luci.js reacts to `poll-start` by showing the header
	 * indicator "poll-status" -> "Refreshing". The theme draws that
	 * indicator as the small spinner in the top bar, i.e. the same live
	 * update spinner every other LuCI app has. Plain setInterval() never
	 * fires those events, which is why the spinner was missing here.
	 *
	 * The poll class must not be touched before `luci-loaded`: LuCI only
	 * installs the poll-start listener once setupDOM() has completed,
	 * so registering earlier would dispatch the event with nobody
	 * listening and the spinner would never appear.
	 *
	 * Naming gotcha: the LuCI instance only carries the UPPERCASE class
	 * aliases (L.dom, L.view, L.Poll, L.Request, L.Class). The lowercase
	 * `L.poll` does NOT exist on the instance - it lives only in the
	 * internal module map reachable via `require('poll')`. Testing for
	 * `L.poll` therefore always fails and silently drops the page back
	 * to plain timers, which is why the header spinner never showed.
	 */
	var scheduled = false, requested = false;

	function attachPoll(Poll) {
		if (scheduled || !Poll || typeof Poll.add !== 'function')
			return false;
		scheduled = true;
		Poll.add(refreshStatus, 3);   /* interval is in seconds */
		Poll.add(refreshLog,    3);
		Poll.add(refreshLive,   5);
		return true;
	}

	function startPolling() {
		if (scheduled) return;
		if (typeof L === 'undefined' || !L || !L.loaded) return;

		/* L.Poll is the documented legacy alias; accept L.poll too in
		 * case a future build renames it. */
		if (attachPoll(L.Poll || L.poll)) return;

		/* Older LuCI without the alias: resolve the module instead. */
		if (!requested && typeof L.require === 'function') {
			requested = true;
			L.require('poll').then(attachPoll, function() { requested = false; });
		}
	}

	function startFallback() {
		if (scheduled) return;
		scheduled = true;
		setInterval(refreshStatus, 3000);
		setInterval(refreshLog,    3000);
		setInterval(refreshLive,   5000);
	}

	document.addEventListener('luci-loaded', startPolling, { once: true });

	/* `luci-loaded` may already have fired before this script was parsed,
	 * so poll briefly for it, then fall back to plain timers so the page
	 * keeps working even if the LuCI runtime never signals readiness. */
	var tries = 0;
	var waiter = setInterval(function () {
		startPolling();
		if (scheduled || ++tries > 50) clearInterval(waiter);
		if (!scheduled && tries > 50) startFallback();
	}, 100);

	/* first paint, before the first poll tick */
	refreshStatus(); refreshLive(); refreshLog();
})();
</script>
HTMLEOF
log_success "Frontend view created."

# ------------------------------------------
# 7. CBI MODEL - STATUS TAB (dashboard + global settings)
# ------------------------------------------
cat > "/usr/lib/lua/luci/model/cbi/sshplus_manager.lua" <<'CBIEOF'
local sys  = require "luci.sys"

local m = Map("sshplus", "SSHPlus Manager",
	"Manage the SSH tunnel. The connection profiles live on the " ..
	"<b>Profiles</b> tab at the top of this page. " ..
	"Settings here are applied by the <b>Save</b> button below.")

-- Keep passwall node + running service in sync after every commit/apply.
local synced = false
local function after_commit(self)
	if synced then return end
	synced = true
	sys.call("/usr/bin/sshplus-backend.sh passwall_sync >/dev/null 2>&1")
	local enabled = self:get("sshplus", "global", "enabled")
	if enabled == "0" then
		sys.call("/etc/init.d/sshplus stop >/dev/null 2>&1")
	else
		sys.call("/etc/init.d/sshplus restart >/dev/null 2>&1")
	end
end
m.on_after_commit = after_commit
m.on_after_apply  = after_commit

-- Global -------------------------------------------------
local s_global = m:section(TypedSection, "sshplus", "Global Settings")
s_global.anonymous = true
s_global.addremove = false

local enabled = s_global:option(Flag, "enabled", "Enable SSHPlus",
	"Start the SOCKS5 tunnel at boot and keep it alive.")
enabled.default = "1"
enabled.rmempty = false

local sport = s_global:option(Value, "socks_port", "SOCKS5 port",
	"Local SOCKS5 proxy port advertised to PassWall.")
sport.datatype = "port"
sport.default = "8089"
sport.rmempty = false

local active = s_global:option(ListValue, "active_profile", "Active Profile",
	"The profile used by the tunnel.")
active:value("", "-- Select Profile --")
m.uci:foreach("sshplus", "profile", function(s)
	active:value(s[".name"], string.format("%s@%s", s.user or "user", s.host or "host"))
end)

return m
CBIEOF
log_success "CBI model created."

# ------------------------------------------
# 7b. CBI MODEL - PROFILES TAB
# ------------------------------------------
# Same schema as the section that used to live inside sshplus_manager, so an
# existing /etc/config/sshplus keeps working untouched.
cat > "/usr/lib/lua/luci/model/cbi/sshplus_profiles.lua" <<'CBIEOF2'
local sys = require "luci.sys"
local uci = require("luci.model.uci").cursor()

local m = Map("sshplus", "SSHPlus Profiles",
	"Manage the SSH connection profiles. The tunnel always uses the profile " ..
	"selected on the <b>Status</b> tab under <b>Global Settings</b>. " ..
	"Changes are applied by the <b>Save</b> button below.")

-- Reconnect and refresh the PassWall node after every commit, and drop a
-- dangling "active profile" reference if the selected profile was deleted
-- on this very page.
local synced = false
local function after_commit(self)
	if synced then return end
	synced = true

	local active = uci:get("sshplus", "global", "active_profile")
	if active and active ~= "" and not uci:get("sshplus", active, "host") then
		uci:set("sshplus", "global", "active_profile", "")
		uci:commit("sshplus")
	end

	sys.call("/usr/bin/sshplus-backend.sh passwall_sync >/dev/null 2>&1")
	if uci:get("sshplus", "global", "enabled") == "0" then
		sys.call("/etc/init.d/sshplus stop >/dev/null 2>&1")
	else
		sys.call("/etc/init.d/sshplus restart >/dev/null 2>&1")
	end
end
m.on_after_commit = after_commit
m.on_after_apply  = after_commit

local s_profiles = m:section(TypedSection, "profile", "Connection Profiles")
s_profiles.anonymous = false
s_profiles.addremove  = true
s_profiles.sortable   = true

s_profiles:option(Value, "host", "SSH Host/IP").rmempty = false
s_profiles:option(Value, "user", "SSH Username", "Remote login user").rmempty = false
s_profiles:option(Value, "port", "SSH Port", "Default is 22").placeholder = "22"

local auth = s_profiles:option(ListValue, "auth_method", "Auth Method")
auth:value("password", "Password")
auth:value("key", "Private Key")
auth.default = "password"

local pass = s_profiles:option(Value, "pass", "SSH Password")
pass.password = true
pass:depends("auth_method", "password")

local keyfile = s_profiles:option(Value, "key_file", "Private Key Path")
keyfile:depends("auth_method", "key")
keyfile.placeholder = "/root/.ssh/id_rsa"

return m
CBIEOF2
log_success "Profiles CBI model created."

# ------------------------------------------
# 8. INIT.D SERVICE (procd)
# ------------------------------------------
log_info "Creating service files..."
cat > "${SVC}" <<'INITEOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1
LOG_FILE="/tmp/sshplus.log"

start_service() {
	echo "--- SSHPlus Service Starting at $(date) ---" > "$LOG_FILE"
	procd_open_instance
	procd_set_param command /bin/sh -c "/usr/bin/sshplus_service >> $LOG_FILE 2>&1"
	procd_set_param respawn 3600 5 10
	procd_close_instance
}

stop_service() {
	echo "--- SSHPlus Service Stopping at $(date) ---" >> "$LOG_FILE"
	# no password in argv (sshpass -e is used), so -f patterns are safe
	pkill -f "/usr/bin/sshplus_service" 2>/dev/null
	pkill -x sshpass 2>/dev/null
	pkill -f "ssh .*-D 127.0.0.1" 2>/dev/null
	rm -f /tmp/sshplus_start_time
	echo "--- SSHPlus Service Stopped ---" >> "$LOG_FILE"
}
INITEOF
chmod +x "${SVC}"
log_success "init.d service created."

# ------------------------------------------
# 9. TUNNEL DAEMON
# ------------------------------------------
cat > /usr/bin/sshplus_service <<'SVCEOF'
#!/bin/sh
# SSHPlus tunnel daemon - all output is redirected to /tmp/sshplus.log
# by the procd init script. This process never exits (it sleeps on errors)
# so procd never has to respawn it.

SSH_BIN=$(command -v ssh 2>/dev/null)
[ -n "$SSH_BIN" ] || SSH_BIN="/usr/bin/ssh"

KNOWN_HOSTS="/root/.ssh/sshplus_known_hosts"

while true; do
	ENABLED=$(uci -q get sshplus.global.enabled 2>/dev/null)
	if [ "$ENABLED" != "1" ]; then
		echo "SSHPlus is disabled. Sleeping for 30s..."
		sleep 30
		continue
	fi

	if [ ! -x "$SSH_BIN" ]; then
		echo "FATAL: OpenSSH client not found ($SSH_BIN)."
		echo "Install it with: opkg install openssh-client  |  apk add openssh-client"
		sleep 600
		continue
	fi

	ACTIVE_PROFILE=$(uci -q get sshplus.global.active_profile 2>/dev/null)
	if [ -z "$ACTIVE_PROFILE" ]; then
		echo "ERROR: No active SSHPlus profile is selected."
		echo "Select a profile in LuCI and save. Sleeping for 60s..."
		sleep 60
		continue
	fi

	echo "Reading configuration for profile: $ACTIVE_PROFILE"
	HOST=$(uci -q get "sshplus.$ACTIVE_PROFILE.host" 2>/dev/null)
	USER=$(uci -q get "sshplus.$ACTIVE_PROFILE.user" 2>/dev/null)
	PORT=$(uci -q get "sshplus.$ACTIVE_PROFILE.port" 2>/dev/null)
	AUTH_METHOD=$(uci -q get "sshplus.$ACTIVE_PROFILE.auth_method" 2>/dev/null)
	KEY_FILE=$(uci -q get "sshplus.$ACTIVE_PROFILE.key_file" 2>/dev/null)
	SOCKS_PORT=$(uci -q get sshplus.global.socks_port 2>/dev/null)
	[ -n "$SOCKS_PORT" ] || SOCKS_PORT=8089

	if [ -z "$HOST" ] || [ -z "$USER" ] || [ -z "$PORT" ]; then
		echo "ERROR: Profile '$ACTIVE_PROFILE' is not fully configured."
		echo "Sleeping for 60s..."
		sleep 60
		continue
	fi

	# Password is passed via the SSHPASS *environment* (sshpass -e) so it
	# never shows up in `ps` output.
	PASS=$(uci -q get "sshplus.$ACTIVE_PROFILE.pass" 2>/dev/null)
	SSHPASS="$PASS"
	export SSHPASS

	mkdir -p /root/.ssh
	[ -f "$KNOWN_HOSTS" ] || : > "$KNOWN_HOSTS"
	chmod 700 /root/.ssh 2>/dev/null
	chmod 600 "$KNOWN_HOSTS" 2>/dev/null

	echo "Configuration loaded. Preparing to connect using OpenSSH..."
	date +%s > /tmp/sshplus_start_time

	SSH_CMD_OPTIONS="-T \
		-o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
		-o StrictHostKeyChecking=accept-new \
		-o UserKnownHostsFile=$KNOWN_HOSTS \
		-o NumberOfPasswordPrompts=1 \
		-o ConnectTimeout=15 -o ExitOnForwardFailure=yes \
		-D 127.0.0.1:$SOCKS_PORT -N -p $PORT"

	echo "Executing SSH command..."

	if [ "$AUTH_METHOD" = "key" ]; then
		echo "Authentication Method: Private Key ($KEY_FILE)"
		$SSH_BIN -i "$KEY_FILE" $SSH_CMD_OPTIONS "$USER@$HOST"
	else
		echo "Authentication Method: Password"
		sshpass -e $SSH_BIN $SSH_CMD_OPTIONS "$USER@$HOST"
	fi
	RC=$?

	echo "SSH tunnel disconnected. Exit code: $RC. Reconnecting in 5s..."
	rm -f /tmp/sshplus_start_time
	sleep 5
done
SVCEOF
chmod +x /usr/bin/sshplus_service
log_success "Tunnel daemon created."

# ------------------------------------------
# 10. BACKEND SCRIPT
# ------------------------------------------
cat > /usr/bin/sshplus-backend.sh <<'BEOF'
#!/bin/sh
# SSHPlus backend - called by the LuCI JSON endpoints and by cron.

UCI="/sbin/uci"
[ -x "$UCI" ] || UCI="uci"
CFG="sshplus"
SVC="/etc/init.d/sshplus"
STATUS_JSON="/tmp/sshplus-status.json"
LOGF="/tmp/sshplus.log"
IPF="/tmp/sshplus-ip.txt"
IPTS="/tmp/sshplus-ip.ts"

g() { $UCI -q get "$CFG.global.$1" 2>/dev/null; }
p_get() { $UCI -q get "$CFG.$1.$2" 2>/dev/null; }

is_running() { pgrep -f sshplus_service >/dev/null 2>&1; }

# ---- PassWall / PassWall2 node (current shape: luci-app-passwall2) ----
passwall_sync() {
	PORT=$(g socks_port)
	[ -n "$PORT" ] || PORT=8089

	UPDATED=""
	for PCFG in passwall2 passwall; do
		[ -f "/etc/config/$PCFG" ] || continue

		# creates the section when missing, is a no-op otherwise
		$UCI -q set "$PCFG.SshPlus=nodes" || continue

		$UCI -q set "$PCFG.SshPlus.remarks=Ssh-Plus"
		$UCI -q set "$PCFG.SshPlus.type=Xray"
		$UCI -q set "$PCFG.SshPlus.protocol=socks"
		$UCI -q set "$PCFG.SshPlus.address=127.0.0.1"
		$UCI -q set "$PCFG.SshPlus.port=$PORT"
		$UCI -q set "$PCFG.SshPlus.tls=0"
		$UCI -q set "$PCFG.SshPlus.transport=raw"
		$UCI -q set "$PCFG.SshPlus.tcp_guise=none"
		$UCI -q set "$PCFG.SshPlus.tcp_fast_open=0"
		$UCI -q set "$PCFG.SshPlus.tcpMptcp=0"
		# drop options older SSHPlus versions wrote that are not part of
		# the current nodes shape
		$UCI -q delete "$PCFG.SshPlus.server"
		$UCI -q delete "$PCFG.SshPlus.tcpNoDelay"

		$UCI -q commit "$PCFG"
		UPDATED="$UPDATED $PCFG"
	done

	if [ -n "$UPDATED" ]; then
		echo "PassWall node synced:$UPDATED (port $PORT)"
	else
		echo "PassWall / PassWall2 not installed - node skipped."
	fi
}

# ---- keep the status file fresh (cron) ----
check_status() {
	ENABLED=$(g enabled)
	[ -n "$ENABLED" ] || ENABLED=1
	PROFILE=$(g active_profile)
	SPORT=$(g socks_port)
	[ -n "$SPORT" ] || SPORT=8089

	RUNNING=false
	is_running && RUNNING=true

	STATUS="disabled"
	if [ "$ENABLED" = "1" ] && [ "$RUNNING" = "true" ]; then
		STATUS="active"
		refresh_ip "$SPORT"
	else
		# never show a stale egress IP once the tunnel is down
		rm -f "$IPF" "$IPTS"
		[ "$ENABLED" = "1" ] && STATUS="disconnected"
	fi

	# keep the JSON well-formed no matter what ends up in UCI
	PROFILE=$(printf '%s' "$PROFILE" | sed 's/[^A-Za-z0-9_.-]//g')
	ENABLED=$(printf '%s' "$ENABLED" | tr -cd '01')

	printf '{"status":"%s","enabled":"%s","profile":"%s","running":%s,"socks_port":"%s","time":"%s"}\n' \
		"$STATUS" "$ENABLED" "$PROFILE" "$RUNNING" "$SPORT" "$(date)" > "$STATUS_JSON"
}

# Resolve the egress IP through the tunnel, at most once a minute.
refresh_ip() {
	SPORT="$1"
	NOW=$(date +%s)
	LAST=0
	[ -f "$IPTS" ] && LAST=$(cat "$IPTS" 2>/dev/null)
	[ -n "$LAST" ] || LAST=0

	if [ $((NOW - LAST)) -lt 60 ]; then
		return 0
	fi
	echo "$NOW" > "$IPTS"

	IP=$(curl --max-time 6 --socks5-hostname "127.0.0.1:$SPORT" -s http://ifconfig.me/ip 2>/dev/null | head -n 1 | tr -d '\r\n')
	[ -n "$IP" ] || IP=$(curl --max-time 6 --socks5-hostname "127.0.0.1:$SPORT" -s https://api.ipify.org 2>/dev/null | head -n 1 | tr -d '\r\n')

	if [ -n "$IP" ]; then
		echo "$IP" > "$IPF"
	else
		rm -f "$IPF"
	fi
}

# ---- end to end probe: real SSH login, output must contain the marker ----
test_conn() {
	PROFILE=$(g active_profile)
	if [ -z "$PROFILE" ]; then
		echo "No active profile selected."
		return 1
	fi

	HOST=$(p_get "$PROFILE" host)
	RUSER=$(p_get "$PROFILE" user)
	RPORT=$(p_get "$PROFILE" port)
	AUTH=$(p_get "$PROFILE" auth_method)
	KEY_FILE=$(p_get "$PROFILE" key_file)
	[ -n "$RPORT" ] || RPORT=22

	if [ -z "$HOST" ] || [ -z "$RUSER" ]; then
		echo "Profile '$PROFILE' is incomplete (host/user)."
		return 1
	fi

	mkdir -p /root/.ssh
	KH="/root/.ssh/sshplus_known_hosts"
	[ -f "$KH" ] || : > "$KH"
	chmod 600 "$KH" 2>/dev/null

	SHARED="-p $RPORT -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$KH -o NumberOfPasswordPrompts=1"

	if [ "$AUTH" = "key" ]; then
		echo "Testing key auth ($KEY_FILE) -> $RUSER@$HOST:$RPORT"
		OUT=$(ssh -i "$KEY_FILE" -o BatchMode=yes $SHARED "$RUSER@$HOST" "echo SSHPLUS_TEST_OK" 2>&1)
	else
		PASS=$(p_get "$PROFILE" pass)
		SSHPASS="$PASS"
		export SSHPASS
		echo "Testing password auth -> $RUSER@$HOST:$RPORT"
		OUT=$(sshpass -e ssh $SHARED "$RUSER@$HOST" "echo SSHPLUS_TEST_OK" 2>&1)
	fi
	RC=$?

	echo "$OUT"
	if [ $RC -eq 0 ] && echo "$OUT" | grep -q SSHPLUS_TEST_OK; then
		echo "SSHPLUS_TEST_OK"
		return 0
	fi
	echo "Test failed (exit $RC)."
	return 1
}

case "${1:-}" in
	run)
		ENABLED=$(g enabled)
		if [ "$ENABLED" = "0" ]; then
			echo "SSHPlus is disabled - enable it first."
			exit 1
		fi
		[ -x "$SVC" ] || { echo "Service not installed."; exit 1; }
		"$SVC" restart >/dev/null 2>&1
		echo "Tunnel restarted at $(date)"
		;;
	test)
		test_conn
		;;
	check)
		check_status
		;;
	passwall_sync)
		passwall_sync
		;;
	*)
		echo "Usage: $0 {run|test|check|passwall_sync}"
		exit 1
		;;
esac
BEOF
chmod +x /usr/bin/sshplus-backend.sh
log_success "Backend script created."

# ------------------------------------------
# 10b. TERMINAL CLI  (/usr/bin/sshplus)
# ------------------------------------------
# Plain POSIX sh on purpose: the pre-v16 version used #!/bin/bash + whiptail,
# neither of which exists on a stock OpenWrt, so it died with
# "bad interpreter" the moment anyone tried to run it.
cat > /usr/bin/sshplus <<'CLIEOF'
#!/bin/sh
# SSHPlus management CLI - terminal companion to the LuCI page.

BACK="/usr/bin/sshplus-backend.sh"
SVC="/etc/init.d/sshplus"
LOG="/tmp/sshplus.log"
STATUS_JSON="/tmp/sshplus-status.json"

u() { uci -q "$@"; }
g() { u get "sshplus.$1"; }
sg() { u set "sshplus.$1"; u commit sshplus; }

# pull one value out of /tmp/sshplus-status.json without needing jq/python
jfield() {
	sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\{0,1\}\([^",}]*\)"\{0,1\}.*/\1/p' \
		"$STATUS_JSON" 2>/dev/null | head -n 1
}

usage() {
	cat <<'EOF'
Usage: sshplus <command>

  status            tunnel state, profile, port, uptime, egress IP
  start             enable the tunnel and (re)connect it
  stop              disconnect and disable the tunnel
  restart           (re)connect without touching the enable switch
  test              end-to-end SSH probe of the active profile
  log [N]           last N lines of the tunnel log (default 30)
  port [N]          show or set the local SOCKS5 port
  profile           list the configured profiles
  help              this text

Profiles, passwords and keys are stored in UCI and edited in LuCI:
  PeDitXOS Tools -> SSHPlus -> Status    tunnel, settings, live status
  PeDitXOS Tools -> SSHPlus -> Profiles  connection profiles
EOF
}

cmd_status() {
	if [ ! -x "$BACK" ]; then
		echo "SSHPlus is not installed correctly (missing $BACK)."
		return 1
	fi
	"$BACK" check >/dev/null 2>&1

	if [ ! -f "$STATUS_JSON" ]; then
		echo "No status data yet - try 'sshplus restart'."
		return 1
	fi

	echo "Status      : $(jfield status)"
	echo "Enabled     : $(jfield enabled)"
	echo "Profile     : $(jfield profile)"
	echo "SOCKS5 port : $(jfield socks_port)"
	echo "Uptime      : $(jfield uptime)"
	echo "Egress IP   : $(cat /tmp/sshplus-ip.txt 2>/dev/null || echo '-')"
	echo "Updated     : $(jfield time)"
}

cmd_start() {
	sg global.enabled=1
	"$BACK" run
}

cmd_stop() {
	[ -x "$SVC" ] && "$SVC" stop >/dev/null 2>&1
	sg global.enabled=0
	echo "Tunnel stopped and disabled."
}

cmd_restart() {
	sg global.enabled=1
	"$BACK" run
}

cmd_log() {
	N=${1:-30}
	case "$N" in ''|*[!0-9]*) N=30 ;; esac
	if [ ! -f "$LOG" ]; then
		echo "No log yet ($LOG)."
		return 0
	fi
	tail -n "$N" "$LOG"
}

cmd_port() {
	if [ -z "${1:-}" ]; then
		echo "$(g global.socks_port)"
		return 0
	fi
	case "$1" in
		*[!0-9]*) echo "Port must be a number."; return 1 ;;
	esac
	sg "global.socks_port=$1"
	"$BACK" passwall_sync >/dev/null 2>&1
	echo "SOCKS5 port set to $1 (PassWall / PassWall2 node updated)."
}

cmd_profile() {
	ACT=$(g global.active_profile)
	echo "Active profile: ${ACT:-(none selected)}"
	i=0
	while u get "sshplus.@profile[$i].host" >/dev/null 2>&1; do
		H=$(g "@profile[$i].host"); H=${H:-?}
		U=$(g "@profile[$i].user");  U=${U:-?}
		P=$(g "@profile[$i].port");  P=${P:-?}
		M=$(g "@profile[$i].auth_method"); M=${M:-password}
		printf '  [%d] %s@%s:%s  auth=%s\n' "$i" "$U" "$H" "$P" "$M"
		i=$((i + 1))
	done
	[ "$i" -eq 0 ] && echo "  (no profiles configured)"
	echo
	echo "Choose the active profile in LuCI: PeDitXOS Tools -> SSHPlus -> Status"
}

case "${1:-}" in
	status)   cmd_status ;;
	start)    cmd_start ;;
	stop)     cmd_stop ;;
	restart)  cmd_restart ;;
	test)     "$BACK" test ;;
	log)      shift; cmd_log "$@" ;;
	port)     shift; cmd_port "$@" ;;
	profile)  cmd_profile ;;
	help|-h|--help|"") usage ;;
	*)
		echo "Unknown command: $1"
		echo
		usage
		exit 1
		;;
esac
CLIEOF
chmod +x /usr/bin/sshplus
log_success "Terminal CLI created (/usr/bin/sshplus)."

# ------------------------------------------
# 11. UCI MIGRATION + PASSWALL SYNC
# ------------------------------------------
/usr/bin/sshplus-backend.sh passwall_sync

# ------------------------------------------
# 12. CRON JOB (keep /tmp/sshplus-status.json fresh)
# ------------------------------------------
(crontab -l 2>/dev/null | grep -v "sshplus-backend") | crontab -
(crontab -l 2>/dev/null; echo "*/1 * * * * /usr/bin/sshplus-backend.sh check >/dev/null 2>&1") | crontab -
log_success "Cron job set."

# ------------------------------------------
# 13. RPCD ACL
# ------------------------------------------
mkdir -p /usr/share/rpcd/acl.d
cat > "/usr/share/rpcd/acl.d/${APP_NAME}.json" <<ACLEOF
{
	"${APP_NAME}": {
		"description": "PeDitXOS ${APP_TITLE} API",
		"read": {
			"uci": ["${APP_NAME}.*"]
		},
		"write": {
			"uci": ["${APP_NAME}.*"]
		}
	}
}
ACLEOF
/etc/init.d/rpcd restart 2>/dev/null
log_success "RPCD ACL configured."

# ------------------------------------------
# 14. ENABLE + START
# ------------------------------------------
log_info "Enabling and restarting the service..."
[ "$(uci -q get ${UCI_CFG}.global.enabled)" = "0" ] && log_warn "SSHPlus is disabled in UCI - tunnel will not start."
"${SVC}" enable 2>/dev/null
"${SVC}" restart 2>/dev/null

# prime the status file so the view has data immediately
/usr/bin/sshplus-backend.sh check >/dev/null 2>&1

# ------------------------------------------
# 15. CLEAR LUCI CACHES
# ------------------------------------------
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache/* /tmp/luci-cache/* 2>/dev/null

# ------------------------------------------
# 16. FINAL
# ------------------------------------------
log_success "${APP_TITLE} installed!"
log_info "LuCI menu: PeDitXOS Tools -> ${APP_TITLE}  (tabs: Status / Profiles)"
log_info "Terminal CLI: sshplus {status|start|stop|restart|test|port|profile|log}"
log_info "API: /cgi-bin/luci/admin/peditxos/sshplus_api/{status,save,run,test,live,toggle,log,clear_log}"
log_info "Package manager used: $PKG"

cat <<'BANNEREOF'
  ______     _____  _   _   _   _____
 (_____ \   (____ \(_)_  \ \ / /   /   / ___ \
  _____) )___ _   \ \ _| |_  \ \/ /   | |   | | ___
 |  ____/ _  ) |   | | |  _)  )  (    | |   | |/___)
 | |   ( (/ /| |__/ /| | |__ / /\ \   | |___| |___ |
 |_|    \____)_____/ |_|\___)_/  \_\   \_____/(___/

                                     SSHPlus by PeDitX
BANNEREOF
