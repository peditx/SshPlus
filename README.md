# SSHPlus Manager for OpenWrt
[![Visitor Badge](https://img.shields.io/badge/Chat%20on-Telegram-blue.svg)](https://t.me/peditx) [![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

[**English**](README.md) | [**فارسی**](README_fa.md) | [**简体中文**](README-ch.md) | [**Русский**](README_ru.md)

![Banner](https://raw.githubusercontent.com/peditx/luci-theme-peditx/refs/heads/main/luasrc/brand.png)

**The first comprehensive SSH tunneling solution natively integrated with PassWall on OpenWrt systems**

---

## 🚀 Features
- 🔐 OpenSSH Server/Client integration
- 🌐 SOCKS5 Proxy (Port 8089) creation
- 🛡️ Full PassWall/PassWall2 integration
- 📊 Real-time connection monitoring
- 📜 LuCI web interface **and** a terminal CLI (`sshplus`)
- 🔄 Auto-reconnect functionality
- 🧩 Compatible with all OpenWrt-supported architectures

---


## ⚙️ Supported Architectures
SSHPlus supports all OpenWrt-compatible CPU architectures, including:

- `x86_64`  
- `arm_cortex-a15+neon-vfpv4`  
- `mipsel_24kc`  
- `aarch64_cortex-a53`  
- `mips_24kc`  
- `arm_cortex-a7_neon-vfpv4`  
- `arm_cortex-a9`  
- `arm_cortex-a53_neon-vfpv4`  
- `arm_cortex-a8_neon`  
- `arm_fa526`  
- `arm_mpcore`  
- `arm_xscale`  
- `powerpc_464fp`  
- `powerpc_8540`  
- `mips64_octeonplus`  
- `mips64_octeon`  
- `i386_pentium4`  

*Full compatibility list available in [OpenWrt documentation](https://openwrt.org/docs/guide-user/additional-software/package-installation)*

---

## 📥 Installation
Run this single command in your OpenWrt terminal:

```bash
rm -f *.sh && wget https://raw.githubusercontent.com/peditx/SshPlus/refs/heads/main/Files/install_sshplus.sh && sh install_sshplus.sh

```

---

## ✨ Key Capabilities
1. **Secure SSH Tunneling**  
   Create SOCKS5 proxies carried inside an OpenSSH session. The cipher is the one OpenSSH negotiates with your server (typically ChaCha20-Poly1305 or AES-GCM) — SSHPlus does not pick or add one of its own.

2. **PassWall Integration**  
   Direct integration with popular OpenWrt proxy solutions

3. **Connection Management**  
   From the LuCI page (**PeDitXOS Tools → SSHPlus** — tabs **Status** / **Profiles**) or from the terminal:
   ```
   sshplus status   # state, profile, port, uptime, egress IP
   sshplus start    # enable and connect
   sshplus test     # end-to-end SSH probe
   ```
   - Start/Stop tunnels
   - Edit configurations
   - Monitor active connections

4. **Auto-Service Creation**  
   Persistent connections survive reboots via init.d service

---

## 📜 About This Innovation
**SSHPlus** represents the first native implementation of:
- Full OpenSSH integration in OpenWrt
- Web (LuCI) and terminal (CLI) SSH tunnel management
- Automatic PassWall configuration
- Service persistence through init.d

*Developed specifically for OpenWrt's unique environment*

---

## 🔧 Requirements
- OpenWrt 21.02 or newer — `opkg` up to 24.10, `apk` on 25.12 and later
- 8MB+ free storage
- Active internet connection
- `curl` — SSHPlus installs it, and **it must stay installed**: `luci-app-passwall2`'s connectivity check calls `curl` from Lua and dies with `HTTP 500` / `attempt to perform arithmetic on local 'use_time'` when it is missing.

> ⚠️ **Upgrading from SSHPlus v15?** Its uninstaller ran `opkg remove curl`, which
> broke PassWall2's connectivity check. Run the v16 installer — it restores `curl`
> automatically (the uninstaller does too). By hand:
> `apk add curl` (25.12+) or `opkg install curl` (≤ 24.10).

---

## 📬 Support & Contact
**Website:**  
[https://peditxos.ir](https://peditxos.ir)

---

## 📄 License
**Copyright © 2026 PeDitXOS**  
*This project is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0) — see [LICENSE](LICENSE).*  
*Note: older revisions of this README said MIT and GPL-3.0; the LICENSE file has always been AGPL-3.0.*

---

## 🙏 Special Thanks
- Inspired by [PeDitXOS](https://peditxos.ir)
- Built for the OpenWrt community
- Powered by PeDitX



© PeDitX 2025 | Telegram: [@peditx](https://t.me/peditx)
