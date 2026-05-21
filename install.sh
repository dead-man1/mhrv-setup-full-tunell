#!/bin/bash
# mhrv-rs Tunnel Node — نصب خودکار (v2.0)
# استفاده: PORT="..." AUTH="..." SSH_PORT="..." bash <(curl -fsSL ...)
#
# بهبودها نسبت به نسخه قبلی:
#  - validation سفت AUTH (حداقل ۱۶ کاراکتر، رد کلیدهای ضعیف)
#  - تشخیص و راهنمایی اگه سرویس دیگه‌ای پورت رو bind کرده (rfc 403 ها)
#  - پاکسازی کامل نصب قبلی (کانتینر + image stale)
#  - IP detection با چند fallback (آی‌پی‌فای، icanhazip، ipinfo)
#  - memory limit برای کانتینر (سرورهای کوچک)
#  - تشخیص دقیق علت خطا + راه‌حل اختصاصی

set -e
LOG=/tmp/mhrv-install.log
> $LOG
export DEBIAN_FRONTEND=noninteractive

# ╔════════════════════════════════════════════════╗
# ║  چک‌های اولیه                                   ║
# ╚════════════════════════════════════════════════╝

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ این اسکریپت باید با root اجرا بشه"
  echo "   اگه root نیستی: sudo -i  (یا sudo قبل دستور بذار)"
  exit 1
fi

# ── validation PORT ──
if [ -z "$PORT" ] || ! echo "$PORT" | grep -qE '^[0-9]+$' || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo "❌ خطا: PORT معتبر نیست"
  echo "   مثال درست: PORT=\"8080\""
  exit 1
fi

# ── validation SSH_PORT ──
if [ -z "$SSH_PORT" ] || ! echo "$SSH_PORT" | grep -qE '^[0-9]+$' || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
  echo "❌ خطا: SSH_PORT معتبر نیست"
  echo "   مثال درست: SSH_PORT=\"22\"  (یا پورت SSH واقعی سرورت)"
  exit 1
fi

# ── validation AUTH (مهم‌ترین چک!) ──
if [ -z "$AUTH" ]; then
  echo "❌ خطا: AUTH خالیه"
  echo "   AUTH یه کلید مخفی هست — نه نام و فامیل!"
  echo "   مثال درست: AUTH=\"a3f9c8b2e1d04f5a7c8b9d0e1f2a3b4c\""
  exit 1
fi

if [ "${#AUTH}" -lt 16 ]; then
  echo "❌ خطا: AUTH خیلی کوتاهه (فقط ${#AUTH} کاراکتر داره)"
  echo ""
  echo "   AUTH باید حداقل ۱۶ کاراکتر باشه و یه رشته رندوم باشه."
  echo "   ❌ نام و فامیل قبول نیست (مثل '${AUTH}')"
  echo "   ❌ کلمات ساده قبول نیست (مثل 'password', '123456')"
  echo "   ✅ یه رشته رندوم hex مثل: a3f9c8b2e1d04f5a"
  echo ""
  echo "   راه ساخت کلید رندوم:"
  echo "     در ترمینال خود سرور: openssl rand -hex 16"
  echo ""
  echo "   یا در صفحه تعاملی، دکمه «🎲 تولید کلید رندوم» رو بزن"
  exit 1
fi

# الگوهای رایج اشتباه (نام معمول، کلمات ساده)
if echo "$AUTH" | grep -qiE '^(admin|root|password|test|user|kian|amir|mahdi|ali|reza|name|123)'; then
  echo "⚠️  هشدار: AUTH شبیه نام یا کلمه ساده‌ست."
  echo "    این ناامنه. پیشنهاد می‌شه از کلید رندوم استفاده کنی."
  echo "    اگه واقعا می‌خوای ادامه بدی، Ctrl+C بزن، AUTH رو عوض کن، دوباره اجرا کن"
  echo "    در غیر این صورت ۵ ثانیه دیگه ادامه می‌دم..."
  sleep 5
fi

# چک کاراکترهای خطرناک
if echo "$AUTH" | grep -qE '[ "\$\\`'\''!&;<>|*?]'; then
  echo "❌ خطا: AUTH شامل کاراکتر مشکل‌ساز برای shell یا docker است"
  echo "   فقط از حروف، اعداد، و این کاراکترها استفاده کن: @ . _ -"
  echo "   پیشنهاد می‌شه فقط hex استفاده کنی: openssl rand -hex 16"
  exit 1
fi

# ╔════════════════════════════════════════════════╗
# ║  پاکسازی نصب قبلی                              ║
# ╚════════════════════════════════════════════════╝

# اگه قبلاً mhrv-tunnel نصب بوده، پاکش کن
if command -v docker >/dev/null 2>&1; then
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^mhrv-tunnel$"; then
    echo "🧹 نصب قبلی mhrv-tunnel پیدا شد — در حال پاکسازی..."
    docker rm -f mhrv-tunnel >> $LOG 2>&1 || true
    sleep 2
  fi
fi

# چک اینکه آیا پورت توسط چیز دیگه‌ای bind شده (قبل از نصب)
if command -v ss >/dev/null 2>&1; then
  BOUND_LINE=$(ss -lntp 2>/dev/null | awk -v port=":${PORT}\$" '$4 ~ port' | head -1)
  if [ -n "$BOUND_LINE" ]; then
    BOUND_PID=$(echo "$BOUND_LINE" | grep -oP 'pid=\K[0-9]+' | head -1 || echo "")
    BOUND_NAME=""
    if [ -n "$BOUND_PID" ]; then
      BOUND_NAME=$(ps -o comm= -p $BOUND_PID 2>/dev/null || echo "unknown")
    fi
    echo "❌ خطا: پورت ${PORT} توسط سرویس دیگه‌ای استفاده می‌شه"
    [ -n "$BOUND_NAME" ] && echo "   سرویس: '$BOUND_NAME' (PID: $BOUND_PID)"
    echo ""
    echo "   راه‌حل ۱: پورت دیگه‌ای انتخاب کن (مثلاً 8888 یا 9090)"
    if [ -n "$BOUND_PID" ]; then
      echo "   راه‌حل ۲: سرویس فعلی رو stop کن:"
      echo "             kill $BOUND_PID"
    fi
    echo "   راه‌حل ۳: اگه nginx/apache/caddy هست و نیاز نداری:"
    echo "             systemctl stop nginx apache2 caddy 2>/dev/null"
    echo "             systemctl disable nginx apache2 caddy 2>/dev/null"
    echo ""
    echo "   دیدن جزئیات: ss -lntp | grep :${PORT}"
    exit 1
  fi
fi

# ╔════════════════════════════════════════════════╗
# ║  نصب                                            ║
# ╚════════════════════════════════════════════════╝

echo "⏳ در حال نصب... لاگ: $LOG"
echo "   (۱-۳ دقیقه طول می‌کشه، صبور باش)"
echo ""

(
echo "[1/5] آماده‌سازی سیستم..."
dpkg --configure -a >> $LOG 2>&1 || true
apt-get update -qq >> $LOG 2>&1

# نصب فقط چیزایی که نیست (سرعت بیشتر)
NEED=""
command -v docker >/dev/null 2>&1 || NEED="$NEED docker.io"
command -v curl >/dev/null 2>&1 || NEED="$NEED curl"
command -v ufw >/dev/null 2>&1 || NEED="$NEED ufw"
command -v ss >/dev/null 2>&1 || NEED="$NEED iproute2"

if [ -n "$NEED" ]; then
  echo "      نصب پیش‌نیازها: $NEED"
  apt-get install -y -q $NEED >> $LOG 2>&1
fi

# مطمئن شو Docker در حال اجراست
systemctl enable docker --now >> $LOG 2>&1 || true

# صبر تا Docker آماده بشه
for i in 1 2 3 4 5; do
  docker info >/dev/null 2>&1 && break
  sleep 2
done

echo "[2/5] تنظیم Firewall..."
ufw --force reset >> $LOG 2>&1 || true
ufw default deny incoming >> $LOG 2>&1
ufw default allow outgoing >> $LOG 2>&1
ufw allow ${SSH_PORT}/tcp comment "SSH" >> $LOG 2>&1
ufw allow ${PORT}/tcp comment "mhrv-tunnel" >> $LOG 2>&1
ufw --force enable >> $LOG 2>&1

echo "[3/5] دانلود image (آخرین نسخه)..."
# پاک کردن image قدیمی برای pull تازه
docker rmi ghcr.io/therealaleph/mhrv-tunnel-node:latest >> $LOG 2>&1 || true
docker pull ghcr.io/therealaleph/mhrv-tunnel-node:latest >> $LOG 2>&1

echo "[4/5] راه‌اندازی container..."
docker rm -f mhrv-tunnel >> $LOG 2>&1 || true

# با memory limit (مناسب برای سرورهای ۱-۲GB)
docker run -d --name mhrv-tunnel \
  --restart unless-stopped \
  --memory="512m" --memory-swap="1g" \
  -p ${PORT}:${PORT} \
  -e PORT=${PORT} \
  -e TUNNEL_AUTH_KEY="${AUTH}" \
  ghcr.io/therealaleph/mhrv-tunnel-node:latest >> $LOG 2>&1

echo "[5/5] چک سلامت..."
sleep 8

# چک container running
CSTATE=$(docker inspect -f "{{.State.Status}}" mhrv-tunnel 2>/dev/null || echo "missing")

# چک پورت listening
PORT_OK="no"
if ss -lntH 2>/dev/null | awk '{print $4}' | grep -qE ":${PORT}$"; then
  PORT_OK="yes"
fi

# چک HTTP response — اگه body شامل تگ HTML یا "Forbidden" بود، یعنی سرویس اشتباه bind کرده
HTTP_BODY=$(curl -s -m 5 http://127.0.0.1:${PORT}/ 2>/dev/null || echo "")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 http://127.0.0.1:${PORT}/ 2>/dev/null)

WRONG_SERVICE="no"
if echo "$HTTP_BODY" | grep -qiE '<html|<!DOCTYPE|forbidden|"google"|nginx|apache' 2>/dev/null; then
  WRONG_SERVICE="yes"
fi

# IP عمومی با چند fallback
PIP=""
for src in "https://api.ipify.org" "https://icanhazip.com" "https://ipinfo.io/ip" "https://ifconfig.me"; do
  RESP=$(curl -4s -m 5 "$src" 2>/dev/null | head -c 45 | tr -d '\n\r ' || true)
  if echo "$RESP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
    PIP="$RESP"
    break
  fi
done

# اگه هیچ source ای IP نداد، از hostname استفاده کن
if [ -z "$PIP" ]; then
  PIP=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -z "$PIP" ] && PIP="نامشخص"
fi

# تشخیص نهایی + علت خطا
H="bad"
REASON=""
if [ "$CSTATE" = "running" ] && [ "$PORT_OK" = "yes" ] && [ "$WRONG_SERVICE" = "no" ] && [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
  H="ok"
elif [ "$WRONG_SERVICE" = "yes" ]; then
  REASON="WRONG_SERVICE"
elif [ "$CSTATE" != "running" ]; then
  REASON="CONTAINER_DEAD"
elif [ "$PORT_OK" = "no" ]; then
  REASON="PORT_NOT_LISTENING"
elif [ "$HTTP_CODE" = "000" ]; then
  REASON="NO_RESPONSE"
fi

echo "RESULT:${H}:${PIP}:${REASON}" >> $LOG
) 2>> $LOG

# ╔════════════════════════════════════════════════╗
# ║  نمایش نتیجه                                   ║
# ╚════════════════════════════════════════════════╝

RESULT=$(grep "RESULT:" $LOG | tail -1)
H=$(echo $RESULT | cut -d: -f2)
PIP=$(echo $RESULT | cut -d: -f3)
REASON=$(echo $RESULT | cut -d: -f4)

echo ""
if [ "$H" = "ok" ]; then
  echo "╔════════════════════════════════════════════════╗"
  echo "║                                                ║"
  echo "║          ✅  نصب با موفقیت انجام شد            ║"
  echo "║                                                ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
  echo "┌─ اطلاعات سرور شما ──────────────────────────────"
  echo "│"
  echo "│   🌐 IP سرور      :  ${PIP}"
  echo "│   🔌 پورت تونل    :  ${PORT}"
  echo "│   🔑 کلید AUTH    :  ${AUTH}"
  echo "│"
  echo "└─────────────────────────────────────────────────"
  echo ""
  echo "📋 مراحل بعدی:"
  echo ""
  echo "  1️⃣  به صفحه‌ی تنظیمات برگرد:"
  echo "      https://kian-irani.github.io/mhrv-setup-full-tunell/"
  echo ""
  echo "  2️⃣  در سربرگ «📝 Apps Script» کد آماده‌شده رو"
  echo "      کپی کن و در script.google.com پیست کن"
  echo ""
  echo "  3️⃣  Deploy → New deployment → Web app"
  echo "      Execute as: Me  |  Access: Anyone"
  echo ""
  echo "  4️⃣  Deployment ID رو در اپ mhrv-rs وارد کن"
  echo "      همراه با AUTH key بالا"
  echo ""
  echo "💡 سرویس بعد از ریستارت VPS هم خودکار روشن می‌شه ✅"
  echo ""
  echo "🔧 برای چک وضعیت بعداً:"
  echo "   PORT=\"${PORT}\" bash <(curl -fsSL https://raw.githubusercontent.com/KIAN-IRANI/mhrv-setup-full-tunell/main/check.sh)"
  echo ""
else
  echo "╔════════════════════════════════════════════════╗"
  echo "║          ❌  نصب با خطا مواجه شد               ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""

  case "$REASON" in
    WRONG_SERVICE)
      echo "⚠️  پورت ${PORT} توسط سرویس دیگه‌ای استفاده می‌شه"
      echo "    (احتمالاً nginx، apache، caddy، یا Cloudflare tunnel)"
      echo ""
      echo "    پاسخی که از پورت گرفتیم:"
      echo "    ─────────────────────────────────"
      curl -s -m 3 http://127.0.0.1:${PORT}/ 2>/dev/null | head -10
      echo "    ─────────────────────────────────"
      echo ""
      echo "    🔧 راه‌حل:"
      echo ""
      echo "    گزینه ۱: سرویس مزاحم رو خاموش کن"
      echo "      ss -lntp | grep :${PORT}    # ببین کی پورت رو گرفته"
      echo "      systemctl stop nginx apache2 caddy 2>/dev/null"
      echo "      systemctl disable nginx apache2 caddy 2>/dev/null"
      echo "      سپس دوباره install اجرا کن"
      echo ""
      echo "    گزینه ۲: پورت دیگه‌ای انتخاب کن (مثلاً 8888 یا 9090)"
      echo "      PORT=\"8888\" AUTH=\"${AUTH}\" SSH_PORT=\"${SSH_PORT}\" \\"
      echo "        bash <(curl -fsSL .../install.sh)"
      ;;
    CONTAINER_DEAD)
      echo "⚠️  کانتینر mhrv-tunnel اجرا نشد"
      echo ""
      echo "    لاگ کانتینر:"
      echo "    ─────────────────────────────────"
      docker logs --tail 20 mhrv-tunnel 2>&1 | head -25
      echo "    ─────────────────────────────────"
      echo ""
      echo "    🔧 احتمالاً مشکل از AUTH یا memory هست. با پشتیبانی تماس بگیر."
      ;;
    PORT_NOT_LISTENING)
      echo "⚠️  کانتینر اجرا شد ولی پورت ${PORT} listening نیست"
      echo "    احتمالاً مشکل docker networking یا firewall"
      echo ""
      docker logs --tail 15 mhrv-tunnel 2>&1 | head -20
      ;;
    NO_RESPONSE)
      echo "⚠️  پورت listening هست ولی پاسخ نمی‌ده"
      echo "    شاید tunnel-node هنوز در حال راه‌اندازیه — یه دقیقه صبر کن"
      echo "    و check.sh رو اجرا کن"
      ;;
    *)
      echo "آخرین خطوط لاگ:"
      echo "─────────────────────────────────"
      tail -20 $LOG 2>/dev/null
      echo "─────────────────────────────────"
      ;;
  esac

  echo ""
  echo "🔍 لاگ کامل: cat $LOG"
  echo "🆘 پشتیبانی: @Kian_irani_t"
fi
