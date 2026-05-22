#!/bin/bash
# mhrv-rs Tunnel Node — آپدیت هوشمند (v2.0)
#
# تفاوت با نسخه قبلی:
#  - نسخه pin شده از فایل VERSION ریپو می‌گیره (نه latest کور)
#  - قبل از آپدیت، نسخه فعلی رو ذخیره می‌کنه
#  - اگه آپدیت fail شد، rollback خودکار به نسخه قبلی
#  - هشدار سینک: اگه نسخه جدید نیاز به redeploy داره، می‌گه

set -e
LOG=/tmp/mhrv-update.log
: > $LOG

# ── چک root ──
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ این اسکریپت نیاز به root داره (برای کنترل docker)"
  echo "   اگه root نیستی، اول 'sudo -i' بزن یا 'sudo' جلوش بذار"
  exit 1
fi

# ── validation ──
if [ -z "$PORT" ] || ! echo "$PORT" | grep -qE '^[0-9]+$' || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo "❌ خطا: PORT معتبر نیست (مثال: PORT=\"8080\")"
  exit 1
fi
if [ -z "$AUTH" ] || [ "${#AUTH}" -lt 6 ]; then
  echo "❌ خطا: AUTH معتبر نیست"
  exit 1
fi

# ── خوندن نسخه پایدار از فایل VERSION ──
echo "🔍 چک نسخه پایدار..."
TUNNEL_VERSION=$(curl -sfL "https://raw.githubusercontent.com/KIAN-IRANI/mhrv-setup-full-tunell/main/VERSION" 2>/dev/null \
  | grep "^TUNNEL_VERSION=" | cut -d= -f2 | tr -d '\r\n ')

if [ -z "$TUNNEL_VERSION" ]; then
  echo "⚠️  نتونست نسخه پایدار رو از remote بخونه — از 1.9.33 استفاده می‌کنه"
  TUNNEL_VERSION="1.9.33"
fi
echo "   نسخه پایدار: $TUNNEL_VERSION"

# ── چک نسخه فعلی container ──
CURRENT_IMG=$(docker inspect mhrv-tunnel --format='{{.Config.Image}}' 2>/dev/null || echo "")
echo "   نسخه فعلی:   ${CURRENT_IMG:-نصب نیست}"

TARGET_IMG="ghcr.io/therealaleph/mhrv-tunnel-node:${TUNNEL_VERSION}"

# اگه نسخه فعلی همون پایداره و سالم در حال اجراست، آپدیت نکن
if [ "$CURRENT_IMG" = "$TARGET_IMG" ]; then
  CSTATE=$(docker inspect -f "{{.State.Status}}" mhrv-tunnel 2>/dev/null)
  if [ "$CSTATE" = "running" ]; then
    echo ""
    echo "✅ سرور در حال حاضر روی نسخه پایدار ($TUNNEL_VERSION) هست"
    echo "   هیچ آپدیتی نیاز نیست"
    exit 0
  fi
fi

echo ""
echo "⏳ آپدیت... لاگ: $LOG"

# ── ذخیره image قبلی برای rollback ──
ROLLBACK_IMG="$CURRENT_IMG"
echo "ROLLBACK: $ROLLBACK_IMG" >> $LOG

(
echo "[1/3] دانلود نسخه پایدار: $TUNNEL_VERSION..."
docker pull "$TARGET_IMG"

echo "[2/3] جایگزینی کانتینر..."
docker rm -f mhrv-tunnel 2>/dev/null || true

docker run -d --name mhrv-tunnel \
  --restart unless-stopped \
  --memory="512m" --memory-swap="1g" \
  -p ${PORT}:${PORT} \
  -e PORT=${PORT} \
  -e TUNNEL_AUTH_KEY="${AUTH}" \
  "$TARGET_IMG"

sleep 6

echo "[3/3] چک سلامت..."
PORT_OK="no"
if ss -lntH 2>/dev/null | awk '{print $4}' | grep -qE ":${PORT}$"; then
  PORT_OK="yes"
fi
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 http://127.0.0.1:${PORT}/ 2>/dev/null)
CSTATE=$(docker inspect -f "{{.State.Status}}" mhrv-tunnel 2>/dev/null)

H="bad"
if [ "$CSTATE" = "running" ] && [ "$PORT_OK" = "yes" ] && [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
  H="ok"
fi
echo "RESULT:${H}" >> $LOG
) >> $LOG 2>&1

H=$(grep RESULT: $LOG | tail -1 | cut -d: -f2)

# ── rollback اگه fail شد ──
if [ "$H" != "ok" ] && [ -n "$ROLLBACK_IMG" ] && [ "$ROLLBACK_IMG" != "$TARGET_IMG" ]; then
  echo ""
  echo "⚠️  آپدیت ناموفق — در حال rollback به نسخه قبلی..."
  docker rm -f mhrv-tunnel 2>/dev/null || true
  docker run -d --name mhrv-tunnel \
    --restart unless-stopped \
    --memory="512m" --memory-swap="1g" \
    -p ${PORT}:${PORT} \
    -e PORT=${PORT} \
    -e TUNNEL_AUTH_KEY="${AUTH}" \
    "$ROLLBACK_IMG" >> $LOG 2>&1
  sleep 5
  ROLLBACK_STATE=$(docker inspect -f "{{.State.Status}}" mhrv-tunnel 2>/dev/null)
  if [ "$ROLLBACK_STATE" = "running" ]; then
    echo "✅ Rollback موفق — سرور با نسخه قبلی ($ROLLBACK_IMG) کار می‌کنه"
    echo "   لطفاً با پشتیبانی تماس بگیر: @Kian_irani_t"
  else
    echo "❌ Rollback هم fail شد — لاگ کامل: cat $LOG"
  fi
  exit 1
fi

# ── IP fallback ──
PIP=""
for src in "https://api.ipify.org" "https://icanhazip.com" "https://ipinfo.io/ip"; do
  PIP=$(curl -4s -m 5 "$src" 2>/dev/null | head -c 45 | tr -d '\n\r ' || true)
  if echo "$PIP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
    break
  fi
  PIP=""
done
[ -z "$PIP" ] && PIP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo ""
if [ "$H" = "ok" ]; then
  echo "╔════════════════════════════════════════════════╗"
  echo "║          ✅  آپدیت با موفقیت انجام شد           ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
  echo "┌─ اطلاعات سرور شما ──────────────────────────────"
  [ -n "$PIP" ] && echo "│   🌐 IP سرور      :  ${PIP}"
  echo "│   🔌 پورت تونل    :  ${PORT}"
  echo "│   🔑 کلید AUTH    :  ${AUTH}"
  echo "│   📦 نسخه tunnel  :  ${TUNNEL_VERSION}"
  echo "└─────────────────────────────────────────────────"
  echo ""

  # هشدار سینک — اگه نسخه >= 1.9.32 (zstd) باشه و کاربر اسکریپت قدیمی داشته باشه
  case "$TUNNEL_VERSION" in
    1.9.3[2-9]|1.9.[4-9]*|[2-9].*)
      echo "⚠️  این نسخه شامل zstd compression است (v1.9.32+)."
      echo "    اگه بعد از آپدیت اتصال قطع شد، احتمالاً نیاز به redeploy:"
      echo ""
      echo "    ۱) اپ mhrv-rs رو به آخرین نسخه آپدیت کن (v1.9.32+)"
      echo "    ۲) اسکریپت جدید رو از صفحه تعاملی بگیر"
      echo "    ۳) در Apps Script: کد قدیمی پاک، کد جدید Paste"
      echo "    ۴) Deploy → Manage deployments → ✏️ → New version → Deploy"
      echo ""
      echo "    (اگه همه قدیمیه، سرور به backward-compat می‌مونه)"
      ;;
    *)
      echo "💡 کلید و آدرس عوض نشده — نیازی به redeploy Apps Script نیست ✅"
      ;;
  esac
else
  echo "╔════════════════════════════════════════════════╗"
  echo "║          ❌  آپدیت با خطا مواجه شد              ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
  echo "آخرین خطوط لاگ:"
  echo "─────────────────────────────────"
  tail -15 $LOG 2>/dev/null
  echo "─────────────────────────────────"
  echo ""
  echo "🆘 پشتیبانی: @Kian_irani_t"
fi
