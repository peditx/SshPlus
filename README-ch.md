# **SSHPlus Manager 适用于 OpenWrt**  
[![在 Telegram 上聊天](https://img.shields.io/badge/Chat%20on-Telegram-blue.svg)](https://t.me/peditx) [![许可证: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)  

[**English**](README.md) | [**فارسی**](README_fa.md) | [**简体中文**](README-ch.md) | [**Русский**](README_ru.md)  

![横幅](https://raw.githubusercontent.com/peditx/luci-theme-peditx/refs/heads/main/luasrc/brand.png)  

**首个与 PassWall 深度集成的 OpenWrt 原生 SSH 隧道解决方案**  

---

## 🚀 功能特点  
- 🔐 OpenSSH 服务器/客户端集成  
- 🌐 创建 SOCKS5 代理（端口 8089）  
- 🛡️ 完全支持 PassWall/PassWall2  
- 📊 实时连接监控  
- 📜 LuCI 网页界面**以及**命令行工具（`sshplus`）  
- 🔄 自动重连功能  
- 🧩 兼容所有 OpenWrt 支持的架构  

---

## ⚙️ 支持的架构  
SSHPlus 支持所有与 OpenWrt 兼容的 CPU 架构，包括：  

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

*完整的兼容性列表请参考 [OpenWrt 官方文档](https://openwrt.org/docs/guide-user/additional-software/package-installation)*  

---

## 📥 安装  
在 OpenWrt 终端中运行以下命令：  

```bash
rm -f *.sh && wget https://raw.githubusercontent.com/peditx/SshPlus/refs/heads/main/Files/install_sshplus.sh && sh install_sshplus.sh

```

---

## ✨ 核心功能  

1. **安全 SSH 隧道**  
   在 OpenSSH 会话中创建 SOCKS5 代理。加密算法由 OpenSSH 与服务器协商决定（通常为 ChaCha20-Poly1305 或 AES-GCM），SSHPlus 本身不会额外指定。  

2. **PassWall 集成**  
   直接兼容 OpenWrt 生态内的流行代理解决方案  

3. **连接管理**  
   可在 LuCI 页面（**PeDitXOS Tools → SSHPlus**，顶部标签：**Status** / **Profiles**）或命令行中操作：
   ```
   sshplus status   # 状态、配置、端口、连接时长、出口 IP
   sshplus start    # 启用并连接
   sshplus test     # 端到端 SSH 探测
   ```
   - 启动/停止隧道  
   - 编辑配置  
   - 监控活动连接  

4. **自动创建服务**  
   通过 init.d 服务确保连接在系统重启后仍然保持稳定  

---

## 📜 关于此项目  
**SSHPlus** 是首个实现以下功能的原生 OpenWrt 解决方案：  
- 完整的 OpenSSH 集成  
- 通过网页（LuCI）和命令行（CLI）管理 SSH 隧道  
- 自动 PassWall 配置  
- 通过 init.d 进行服务持久化  

*专为 OpenWrt 生态系统设计*  

---

## 🔧 运行要求  
- OpenWrt 21.02 或更新版本 — 24.10 及以下使用 `opkg`，25.12 及以上使用 `apk`  
- 至少 8MB 的可用存储空间  
- 可用的互联网连接  
- `curl` — 安装程序会自动安装，且**必须保留**：`luci-app-passwall2` 的连接检测依赖它，缺失时会返回 `HTTP 500`。

> ⚠️ **从 SSHPlus v15 升级？** 其卸载脚本会执行 `opkg remove curl`，从而破坏 PassWall2 的连接检测。运行 v16 安装程序即可自动恢复 `curl`；也可手动执行：`apk add curl`（25.12+）或 `opkg install curl`（≤ 24.10）。

---

## 📬 支持与联系  
**Telegram 频道:**  
[https://t.me/peditx](https://t.me/peditx)  

---

## 📄 许可证  
**© 2025 PeDitX**  
*本项目采用 GNU Affero General Public License v3.0（AGPL-3.0）— 详见 [LICENSE](LICENSE)。*  
*注：本 README 的旧版本曾标注 MIT 与 GPL-3.0；LICENSE 文件始终为 AGPL-3.0。*  

---

## 🙏 特别感谢  
- 受 [EZpasswall](https://github.com/peditx/EZpasswall) 启发  
- 专为 OpenWrt 社区打造  
- 由 PeDitX 提供支持  

© PeDitX 2025 | Telegram: [@peditx](https://t.me/peditx)
