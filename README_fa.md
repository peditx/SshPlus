# **مدیر SSHPlus برای OpenWrt**  
[![گفت‌وگو در تلگرام](https://img.shields.io/badge/Chat%20on-Telegram-blue.svg)](https://t.me/peditx) [![مجوز: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)  

[**English**](README.md) | [**فارسی**](README_fa.md) | [**简体中文**](README-ch.md) | [**Русский**](README_ru.md)  

![بنر](https://raw.githubusercontent.com/peditx/luci-theme-peditx/refs/heads/main/luasrc/brand.png)  

**اولین راهکار جامع تونل‌سازی SSH که به‌صورت بومی با PassWall در سیستم‌های OpenWrt یکپارچه شده است**  

---

## 🚀 ویژگی‌ها  
- 🔐 یکپارچه‌سازی سرور/کلاینت OpenSSH  
- 🌐 ایجاد پروکسی SOCKS5 (پورت 8089)  
- 🛡️ ادغام کامل با PassWall/PassWall2  
- 📊 نظارت بر اتصالات در لحظه  
- 📜 رابط وب LuCI **و** ابزار خط فرمان (`sshplus`)  
- 🔄 قابلیت اتصال مجدد خودکار  
- 🧩 سازگار با تمام معماری‌های پشتیبانی‌شده توسط OpenWrt  

---

## ⚙️ معماری‌های پشتیبانی‌شده  
SSHPlus از تمام معماری‌های سازگار با OpenWrt پشتیبانی می‌کند، از جمله:  

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

*لیست کامل سازگاری در [مستندات OpenWrt](https://openwrt.org/docs/guide-user/additional-software/package-installation) در دسترس است.*  

---

## 📥 نصب  
دستور زیر را در ترمینال OpenWrt خود اجرا کنید:  

```bash
rm -f *.sh && wget https://raw.githubusercontent.com/peditx/SshPlus/refs/heads/main/Files/install_sshplus.sh && sh install_sshplus.sh

```

---

## ✨ قابلیت‌های کلیدی  

1. **تونل‌سازی امن SSH**  
   ایجاد پروکسی‌های SOCKS5 داخل یک نشست OpenSSH. الگوریتم رمزنگاری همان است که OpenSSH با سرور مذاکره می‌کند (معمولاً ChaCha20-Poly1305 یا AES-GCM) — SSHPlus رمزنگاری خاصی به آن اضافه نمی‌کند.  

2. **یکپارچگی با PassWall**  
   ادغام مستقیم با راهکارهای پروکسی محبوب OpenWrt  

3. **مدیریت اتصالات**  
   از صفحه LuCI (**PeDitXOS Tools → SSHPlus**، با تب‌های **Status** و **Profiles**) یا از خط فرمان:
   ```
   sshplus status   # وضعیت، پروفایل، پورت، مدت اتصال، IP خروجی
   sshplus start    # فعال‌سازی و اتصال
   sshplus test     # آزمون سرتاسری SSH
   ```
   - راه‌اندازی/توقف تونل‌ها  
   - ویرایش تنظیمات  
   - نظارت بر اتصالات فعال  

4. **ایجاد سرویس خودکار**  
   حفظ اتصالات پایدار حتی پس از ریبوت از طریق سرویس init.d  

---

## 📜 درباره این نوآوری  
**SSHPlus** اولین پیاده‌سازی بومی شامل:  
- یکپارچگی کامل OpenSSH در OpenWrt  
- مدیریت تونل‌های SSH از طریق وب (LuCI) و خط فرمان (CLI)  
- پیکربندی خودکار PassWall  
- پایداری سرویس از طریق init.d  

*طراحی‌شده به‌طور ویژه برای محیط OpenWrt*  

---

## 🔧 الزامات  
- OpenWrt نسخه 21.02 یا جدیدتر — تا 24.10 با `opkg` و از 25.12 به بعد با `apk`  
- حداقل 8 مگابایت فضای ذخیره‌سازی آزاد  
- اتصال اینترنت فعال  
- `curl` — نصب‌کننده آن را نصب می‌کند و **باید باقی بماند**: تست اتصال `luci-app-passwall2` این برنامه را از داخل Lua صدا می‌زند و اگر نباشد با `HTTP 500` و خطای `attempt to perform arithmetic on local 'use_time'` از کار می‌افتد.

> ⚠️ **از SSHPlus v15 ارتقا می‌دهید؟** حذف‌کننده‌ی آن دستور `opkg remove curl` را اجرا می‌کرد و تست اتصال PassWall2 را خراب می‌کرد. نصب‌کننده‌ی v16 را اجرا کنید — `curl` را خودبه‌خود برمی‌گرداند (حذف‌کننده هم همین‌طور). یا دستی: `apk add curl` (25.12+) یا `opkg install curl` (تا 24.10).

---

## 📬 پشتیبانی و تماس  
**کانال تلگرام:**  
[https://t.me/peditx](https://t.me/peditx)  

---

## 📄 مجوز  
**© 2025 PeDitX**  
*این پروژه تحت مجوز GNU Affero General Public License نسخه ۳.۰ (AGPL-3.0) منتشر شده است — به [LICENSE](LICENSE) مراجعه کنید.*  
*توجه: نسخه‌های قدیمی‌تر این README مجوزهای MIT و GPL-3.0 را ذکر می‌کردند؛ فایل LICENSE از ابتدا AGPL-3.0 بوده است.*  

---

## 🙏 سپاس ویژه  
- الهام‌گرفته از [EZpasswall](https://github.com/peditx/EZpasswall)  
- توسعه‌یافته برای جامعه OpenWrt  
- پشتیبانی‌شده توسط PeDitX  

© PeDitX 2025 | تلگرام: [@peditx](https://t.me/peditx)
