<div align="center">

# 🛡️ راهنمای راه‌اندازی mhrv-rs

### راهنمای تعاملی برای فیلترشکن Full Tunnel اندروید

[![English](https://img.shields.io/badge/lang-English-blue?style=flat-square)](README.md)
[![فارسی](https://img.shields.io/badge/lang-فارسی-green?style=flat-square)](README.fa.md)

[![صفحه تعاملی](https://img.shields.io/badge/صفحه%20تعاملی-باز%20کن-3fb950?style=for-the-badge&logo=github)](https://kian-irani.github.io/mhrv-setup-full-tunell/)
[![ربات تلگرام](https://img.shields.io/badge/ربات%20اسکریپت-رایگان-26A5E4?style=for-the-badge&logo=telegram)](https://t.me/Mhrv_script_bot)
[![ربات اشکال‌زدا](https://img.shields.io/badge/ربات%20اشکال‌زدا-AI-e3b341?style=for-the-badge&logo=telegram)](https://t.me/Vpscript_bot)
[![کانال](https://img.shields.io/badge/کانال%20اطلاع‌رسانی-تلگرام-26A5E4?style=for-the-badge&logo=telegram)](https://t.me/kian_irani_cdn_f)

</div>

---

## ⚡ این چیه؟

ابزار کامل راه‌اندازی برای **[mhrv-rs](https://github.com/therealaleph/MasterHttpRelayVPN-RUST)** — یه فیلترشکن که ترافیک گوشی اندرویدت رو از طریق **Google Apps Script** به tunnel-node روی VPS خودت رد می‌کنه.

**ISP فقط یه اتصال TLS به `www.google.com` می‌بینه** — هیچ امضای VPN، هیچ پروتکل قابل تشخیص.

### چطور کار می‌کنه؟

```
📱 گوشی شما
    ↓  TLS — SNI: www.google.com  ← ISP فقط این رو می‌بینه
☁️  Google Edge  (قابل فیلتر نیست)
    ↓
📝 Apps Script  (جی‌میل خودت — رایگان)
    ↓
🖥️  Tunnel Node  (VPS خودت)
    ↓
🌍 اینترنت آزاد
```

---

## ✨ ویژگی‌ها

- 🆓 **کاملاً رایگان** — از سهمیه روزانه گوگل خودت استفاده می‌کنه (۲۰هزار درخواست/روز)
- 🔓 **بدون نیاز به Root** — روی هر اندروید ۷ به بالا کار می‌کنه
- 🛡️ **Full Tunnel واقعی** — بدون نیاز به نصب گواهی (از v1.9.28)
- ⚡ **خودمیزبان** — داده فقط از گوگل → VPS تو → اینترنت
- 🔄 **آپدیت خودکار** — نسخه‌های pin شده با rollback خودکار
- 🌐 **چندسکویی** — اندروید، ویندوز، مک، لینوکس

---

## 🚀 شروع سریع

### ۱. گرفتن اسکریپت (رایگان، ~۳۰ ثانیه)

دو روش داری:

**ساده‌ترین:** [ربات تلگرام](https://t.me/Mhrv_script_bot) → دکمه «دریافت اسکریپت» → تموم.

**یا:** از [صفحه تعاملی](https://kian-irani.github.io/mhrv-setup-full-tunell/) استفاده کن.

### ۲. Deploy در Google Apps Script

۱. [script.google.com](https://script.google.com) → پروژه جدید
۲. اسکریپتی که از مرحله ۱ گرفتی رو Paste کن
۳. **Deploy** → New deployment → Web app
   - Execute as: **Me**
   - Access: **Anyone**
۴. **Deployment ID** رو کپی کن (با `AKfycb...` شروع می‌شه)

### ۳. نصب tunnel-node روی VPS

یه دستور — خودکار Docker نصب می‌کنه، فایروال تنظیم می‌کنه، کانتینر اجرا می‌کنه:

```bash
PORT="8080" AUTH="$(openssl rand -hex 16)" SSH_PORT="22" \
  bash <(curl -fsSL https://raw.githubusercontent.com/KIAN-IRANI/mhrv-setup-full-tunell/main/install.sh)
```

> ⚠️ **AUTH رو نام خودت نذار!** یه کلید مخفی رندوم باشه (حداقل ۱۶ کاراکتر). صفحه تعاملی دکمه 🎲 داره برای ساختن.

### ۴. تنظیم اپ اندروید

[APK mhrv-rs](https://github.com/therealaleph/MasterHttpRelayVPN-RUST/releases/latest) رو دانلود + نصب کن، بعد:

- **Deployment ID** (از مرحله ۲)
- **AUTH key** (از مرحله ۳)
- Mode رو **Full Tunnel (no cert)** کن

تموم. لذت ببر از اینترنت آزاد.

---

## 🩺 ربات اشکال‌زدا (مهم!)

اگه مشکل داشتی، **اول این رو امتحان کن** — هوش مصنوعی، رایگان، فوری:

### 👉 [@Vpscript_bot](https://t.me/Vpscript_bot)

دکمه «اشکال‌زدایی لاگ» رو بزن → به ۴ سوال پاسخ بده → لاگ‌ت رو بفرست → ۱۰-۳۰ ثانیه بعد تشخیص + راه‌حل می‌گیری.

---

## 🆘 پشتیبانی

| منبع | لینک |
|------|------|
| 📢 کانال | [@kian_irani_cdn_f](https://t.me/kian_irani_cdn_f) |
| 💬 گروه گفتگو | [@kiancdn_group](https://t.me/kiancdn_group) |
| 🤖 ربات اسکریپت | [@Mhrv_script_bot](https://t.me/Mhrv_script_bot) |
| 🩺 **ربات اشکال‌زدا** | [@Vpscript_bot](https://t.me/Vpscript_bot) |
| 🆘 پشتیبانی مستقیم | [@Kian_irani_t](https://t.me/Kian_irani_t) |
| 🖥 سرور اختصاصی | [@Kian_irani_vps](https://t.me/Kian_irani_vps) |

---

## 💝 حمایت از پروژه

این پروژه **رایگانه**، ولی هزینه سرور (~۳۰ دلار/ماه) و وقت توسعه واقعیه.

**ترون TRC20** (USDT/USDC/TRX):
```
TEVuoZ7574341zbc8pc5jrrBrgqGGMys5q
```

⚡ سریع، بدون کارمزد، در همه صرافی‌ها موجود

جزئیات کامل: **[DONATE.md](DONATE.md)**

---

## 📄 لایسنس

MIT — به [LICENSE](LICENSE) نگاه کن.

---

<div align="center">

**ساخته‌شده با ❤️ برای اینترنت آزاد**

[⭐ Star کن](https://github.com/KIAN-IRANI/mhrv-setup-full-tunell) اگه دوست داشتی

</div>
