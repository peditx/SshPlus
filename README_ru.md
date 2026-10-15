# **SSHPlus Manager для OpenWrt**  
[![Чат в Telegram](https://img.shields.io/badge/Chat%20on-Telegram-blue.svg)](https://t.me/peditx) [![Лицензия: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)  

[**English**](README.md) | [**فارسی**](README_fa.md) | [**简体中文**](README-ch.md) | [**Русский**](README_ru.md)  

![Баннер](https://raw.githubusercontent.com/peditx/luci-theme-peditx/refs/heads/main/luasrc/brand.png)  

**Первое комплексное решение для SSH-туннелирования, нативно интегрированное с PassWall в системах OpenWrt**  

---

## 🚀 Возможности  
- 🔐 Интеграция сервера/клиента OpenSSH  
- 🌐 Создание SOCKS5-прокси (порт 8089)  
- 🛡️ Полная интеграция с PassWall/PassWall2  
- 📊 Мониторинг соединений в реальном времени  
- 📜 Веб-интерфейс LuCI **и** утилита командной строки (`sshplus`)  
- 🔄 Функция автоматического переподключения  
- 🧩 Совместимость со всеми архитектурами, поддерживаемыми OpenWrt  

---

## ⚙️ Поддерживаемые архитектуры  
SSHPlus поддерживает все архитектуры, совместимые с OpenWrt, включая:  

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

*Полный список совместимых архитектур доступен в [документации OpenWrt](https://openwrt.org/docs/guide-user/additional-software/package-installation).*  

---

## 📥 Установка  
Выполните следующую команду в терминале OpenWrt:  

```bash
rm -f *.sh && wget https://raw.githubusercontent.com/peditx/SshPlus/refs/heads/main/Files/install_sshplus.sh && sh install_sshplus.sh

```

---

## ✨ Основные возможности  

1. **Безопасное SSH-туннелирование**  
   Создание SOCKS5-прокси внутри сеанса OpenSSH. Шифр согласуется OpenSSH с вашим сервером (обычно ChaCha20-Poly1305 или AES-GCM) — SSHPlus не добавляет собственный.  

2. **Интеграция с PassWall**  
   Прямая совместимость с популярными OpenWrt-прокси-решениями  

3. **Управление соединениями**  
   Через страницу LuCI (**PeDitXOS Tools → SSHPlus**, вкладки **Status** / **Profiles**) или из командной строки:
   ```
   sshplus status   # состояние, профиль, порт, время работы, внешний IP
   sshplus start    # включить и подключить
   sshplus test     # сквозная проверка SSH
   ```
   - Запуск/остановка туннелей  
   - Редактирование конфигураций  
   - Мониторинг активных соединений  

4. **Автоматическое создание сервисов**  
   Поддержание постоянных соединений даже после перезагрузки через службу init.d  

---

## 📜 О данном решении  
**SSHPlus** — это первая нативная реализация:  
- Полной интеграции OpenSSH в OpenWrt  
- Управления SSH-туннелями через веб (LuCI) и командную строку (CLI)  
- Автоматической настройки PassWall  
- Сохранения сервиса через init.d  

*Разработано специально для уникальной среды OpenWrt*  

---

## 🔧 Требования  
- OpenWrt 21.02 или новее — `opkg` до 24.10, `apk` начиная с 25.12  
- Минимум 8 МБ свободного пространства  
- Активное интернет-соединение  
- `curl` — ставится автоматически и **должен оставаться**: проверка соединения в `luci-app-passwall2` вызывает его из Lua и падает с `HTTP 500`, если его нет.

> ⚠️ **Обновляетесь с SSHPlus v15?** Его скрипт удаления выполнял `opkg remove curl` и ломал проверку соединения PassWall2. Запустите установщик v16 — он вернёт `curl` автоматически. Вручную: `apk add curl` (25.12+) или `opkg install curl` (≤ 24.10).

---

## 📬 Поддержка и связь  
**Канал в Telegram:**  
[https://t.me/peditx](https://t.me/peditx)  

---

## 📄 Лицензия  
**© 2025 PeDitX**  
*Этот проект распространяется по лицензии GNU Affero General Public License v3.0 (AGPL-3.0) — см. [LICENSE](LICENSE).*  
*Примечание: в старых версиях README указывались MIT и GPL-3.0; файл LICENSE всегда был AGPL-3.0.*  

---

## 🙏 Особая благодарность  
- Вдохновлено проектом [PeDitXOS](https://peditxos.ir)  
- Создано для сообщества OpenWrt  
- Поддерживается PeDitX  

© PeDitX 2025 | Telegram: [@peditx](https://t.me/peditx)
