#!/usr/bin/env python3
"""
sync_upstream.py — همگام‌سازی خودکار با upstream mhrv-rs

هر بار اجرا می‌شه:
1. آخرین release از therealaleph/MasterHttpRelayVPN-RUST می‌گیره
2. CodeFull.gs.template رو با نسخه جدید مقایسه می‌کنه
3. اگه نسخه تغییر کرد:
   a. CodeFull.gs.template رو آپدیت می‌کنه
   b. VERSION → TUNNEL_VERSION جدید + TEMPLATE_LINES جدید
   c. لینک‌های APK در index.html و pc-ios.html رو آپدیت می‌کنه
   d. README.md badge ها آپدیت می‌کنه
   e. CHANGELOG.md یه entry جدید اضافه می‌کنه
4. اگه تغییری نبود، صبر می‌کنه

اجرا: python3 scripts/sync_upstream.py
خروج 0 = همه چیز اوکی، خروج 1 = خطا
"""

import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

UPSTREAM_REPO = "therealaleph/MasterHttpRelayVPN-RUST"
OUR_REPO_DIR = Path(__file__).parent.parent  # یک سطح بالاتر از scripts/


def log(msg, level="INFO"):
    icon = {"INFO": "ℹ️", "OK": "✅", "WARN": "⚠️", "ERROR": "❌"}.get(level, "•")
    print(f"{icon} {msg}", flush=True)


def http_get_json(url, token=None):
    req = urllib.request.Request(url)
    req.add_header("Accept", "application/vnd.github.v3+json")
    req.add_header("User-Agent", "mhrv-sync-bot")
    if token:
        req.add_header("Authorization", f"token {token}")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def http_get_text(url):
    req = urllib.request.Request(url)
    req.add_header("User-Agent", "mhrv-sync-bot")
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")


def get_latest_upstream_release(token=None):
    """آخرین release از upstream"""
    url = f"https://api.github.com/repos/{UPSTREAM_REPO}/releases/latest"
    data = http_get_json(url, token)
    return {
        "tag": data["tag_name"],
        "name": data.get("name", ""),
        "body": data.get("body", ""),
        "published_at": data.get("published_at", ""),
        "assets": [
            {"name": a["name"], "size": a["size"], "url": a["browser_download_url"]}
            for a in data.get("assets", [])
        ],
    }


def get_current_version():
    """نسخه فعلی از فایل VERSION ما"""
    version_file = OUR_REPO_DIR / "VERSION"
    if not version_file.exists():
        return None, None
    content = version_file.read_text()
    tunnel = re.search(r"^TUNNEL_VERSION=(.+)$", content, re.MULTILINE)
    lines = re.search(r"^TEMPLATE_LINES=(.+)$", content, re.MULTILINE)
    return (
        tunnel.group(1).strip() if tunnel else None,
        int(lines.group(1).strip()) if lines else None,
    )


def fetch_upstream_codefull(tag):
    """دانلود CodeFull.gs upstream برای tag مشخص"""
    url = f"https://raw.githubusercontent.com/{UPSTREAM_REPO}/{tag}/assets/apps_script/CodeFull.gs"
    return http_get_text(url)


def fetch_upstream_codefull_main():
    """دانلود از main branch (همیشه فعلی)"""
    url = f"https://raw.githubusercontent.com/{UPSTREAM_REPO}/main/assets/apps_script/CodeFull.gs"
    return http_get_text(url)


def update_template(new_content):
    """دو فایل ذخیره می‌کنه:
    1. CodeFull.gs.upstream  — placeholder های upstream خام (برای ربات با sed)
    2. CodeFull.gs.template  — placeholder های ما %%X%% (برای صفحه با JS)
    """
    upstream_path = OUR_REPO_DIR / "CodeFull.gs.upstream"
    template_path = OUR_REPO_DIR / "CodeFull.gs.template"
    
    # تأیید: باید CHANGE_ME داشته باشه (placeholder upstream)
    if "CHANGE_ME_TO_A_STRONG_SECRET" not in new_content:
        log("CodeFull.gs upstream حاوی placeholder نیست — توقف!", "ERROR")
        return False
    
    # ── ۱. فایل upstream خام (برای ربات روی VPS) ──
    upstream_path.write_text(new_content)
    log(f"CodeFull.gs.upstream آپدیت شد ({len(new_content.splitlines())} خط) — برای ربات", "OK")
    
    # ── ۲. فایل template با placeholder های ما (برای صفحه) ──
    new_template = new_content
    new_template = new_template.replace(
        'const AUTH_KEY = "CHANGE_ME_TO_A_STRONG_SECRET";',
        'const AUTH_KEY = "%%AUTH_KEY%%";',
    )
    new_template = new_template.replace(
        'const TUNNEL_SERVER_URL = "https://YOUR_TUNNEL_NODE_URL";',
        'const TUNNEL_SERVER_URL = "%%TUNNEL_URL%%";',
    )
    new_template = new_template.replace(
        'const TUNNEL_AUTH_KEY = "YOUR_TUNNEL_AUTH_KEY";',
        'const TUNNEL_AUTH_KEY = "%%AUTH_KEY%%";',
    )
    
    # تأیید: ۳ تا placeholder ما باید موجود باشن
    if new_template.count("%%AUTH_KEY%%") != 2 or new_template.count("%%TUNNEL_URL%%") != 1:
        log("جایگزینی placeholder ها ناموفق — توقف!", "ERROR")
        return False
    
    template_path.write_text(new_template)
    log(f"CodeFull.gs.template آپدیت شد ({len(new_content.splitlines())} خط)", "OK")
    return True


def update_version_file(tag, lines):
    """VERSION → نسخه جدید"""
    version_path = OUR_REPO_DIR / "VERSION"
    content = f"""# نسخه tunnel-node که در حال حاضر آزمایش شده و سازگاره
# این فایل توسط install.sh و update.sh خونده می‌شه
# هر بار که نسخه جدید رسمی منتشر شد، تست کن، اگه سالم بود اینجا رو آپدیت کن
# نسخه‌های موجود: https://github.com/{UPSTREAM_REPO}/releases

# فعلی: {tag} — به‌طور خودکار توسط sync-upstream workflow آپدیت می‌شه
TUNNEL_VERSION={tag.lstrip("v")}
TEMPLATE_LINES={lines}
"""
    version_path.write_text(content)
    log(f"VERSION → TUNNEL_VERSION={tag.lstrip('v')}, TEMPLATE_LINES={lines}", "OK")


def update_html_links(old_tag, new_tag):
    """لینک‌های APK در index.html و pc-ios.html رو آپدیت کن"""
    old_v = old_tag.lstrip("v")
    new_v = new_tag.lstrip("v")
    
    if old_v == new_v:
        return 0
    
    changed = 0
    for filename in ["index.html", "pc-ios.html"]:
        path = OUR_REPO_DIR / filename
        if not path.exists():
            continue
        text = path.read_text()
        
        # جایگزینی همه ارجاع‌ها به نسخه قبلی
        # مثال: download/v1.9.33/mhrv-rs-... → download/v1.9.34/mhrv-rs-...
        new_text = text.replace(f"download/v{old_v}/", f"download/v{new_v}/")
        new_text = new_text.replace(f"-v{old_v}.apk", f"-v{new_v}.apk")
        # text در دکمه: "Download APK v1.9.33"
        new_text = new_text.replace(f"v{old_v})", f"v{new_v})")
        new_text = new_text.replace(f"({old_v})", f"({new_v})")
        # توضیحات نسخه‌دار در توصیف
        new_text = new_text.replace(f"(v{old_v})", f"(v{new_v})")
        
        if new_text != text:
            path.write_text(new_text)
            log(f"{filename} آپدیت شد", "OK")
            changed += 1
    
    return changed


def update_readme_badge(old_tag, new_tag):
    """badge دانلود APK در README.md رو آپدیت کن"""
    old_v = old_tag.lstrip("v")
    new_v = new_tag.lstrip("v")
    
    for filename in ["README.md", "README.fa.md"]:
        path = OUR_REPO_DIR / filename
        if not path.exists():
            continue
        text = path.read_text()
        new_text = text.replace(f"download/v{old_v}/", f"download/v{new_v}/")
        new_text = new_text.replace(f"-v{old_v}.apk", f"-v{new_v}.apk")
        new_text = new_text.replace(f"APK%20v{old_v}", f"APK%20v{new_v}")
        new_text = new_text.replace(f"APK v{old_v}", f"APK v{new_v}")
        if new_text != text:
            path.write_text(new_text)
            log(f"{filename} badge آپدیت شد", "OK")


def append_changelog(old_tag, new_tag, upstream_body):
    """یه entry به CHANGELOG.md اضافه کن"""
    path = OUR_REPO_DIR / "CHANGELOG.md"
    if not path.exists():
        log("CHANGELOG.md نیست، رد می‌شم", "WARN")
        return
    
    text = path.read_text()
    
    # تاریخ امروز
    from datetime import datetime
    today = datetime.utcnow().strftime("%Y-%m-%d")
    
    # خلاصه upstream (۲۰۰ کاراکتر اول)
    body_summary = upstream_body.strip().split("\n\n")[0][:400] if upstream_body else ""
    body_summary = body_summary.replace("\n", " ").strip()
    
    new_entry = f"""## [{new_tag.lstrip("v")}] — {today} (auto-synced from upstream)

### Changed
- **Synced to mhrv-rs {new_tag}** (was {old_tag})
- CodeFull.gs.template updated to match upstream
- All download links in `index.html` / `pc-ios.html` / README updated
- VERSION file pin updated to {new_tag.lstrip("v")}

### Upstream notes
> {body_summary if body_summary else "See upstream release notes"}

Auto-synced by `.github/workflows/sync-upstream.yml`

---

"""
    
    # اضافه بعد از "## [Unreleased]" section
    if "## [Unreleased]" in text:
        # پیدا کردن خط بعد از Unreleased
        parts = text.split("## [", 1)
        # اولین ## [ بعد از header
        if "[Unreleased]" in text:
            unreleased_section, rest = text.split("## [Unreleased]", 1)
            # بعد از Unreleased، اولین ## بعدی
            next_section_idx = rest.find("\n## [")
            if next_section_idx > 0:
                # Insert before next section
                new_text = (
                    unreleased_section
                    + "## [Unreleased]"
                    + rest[:next_section_idx]
                    + "\n\n---\n\n"
                    + new_entry
                    + rest[next_section_idx + 2:]  # +2 برای رد کردن \n##
                )
                # درست کردن: بعد از \n## رفت توی new_entry، باید برگرده
                new_text = (
                    unreleased_section
                    + "## [Unreleased]"
                    + rest[:next_section_idx]
                    + new_entry
                    + "## ["
                    + rest[next_section_idx + 5:]  # rest از "\n## [" شروع می‌شه
                )
                path.write_text(new_text)
                log("CHANGELOG.md entry جدید اضافه شد", "OK")
                return
    
    # fallback: اضافه به اول
    path.write_text(new_entry + text)
    log("CHANGELOG.md entry جدید اضافه شد (سادگی)", "OK")


def main():
    log(f"شروع sync با upstream {UPSTREAM_REPO}")
    log(f"working dir: {OUR_REPO_DIR}")
    
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        log("استفاده از GitHub token (rate limit بالاتر)")
    
    # نسخه فعلی ما
    current_tag, current_lines = get_current_version()
    if not current_tag:
        log("VERSION فایل پیدا نشد یا فرمت اشتباه!", "ERROR")
        return 1
    
    current_tag_v = f"v{current_tag}"  # برای مقایسه
    log(f"نسخه فعلی ما: {current_tag_v} ({current_lines} خط)")
    
    # نسخه upstream
    try:
        upstream = get_latest_upstream_release(token)
    except Exception as e:
        log(f"خطا در دریافت upstream release: {e}", "ERROR")
        return 1
    
    log(f"نسخه upstream: {upstream['tag']} ({upstream['published_at'][:10]})")
    
    # مقایسه
    if upstream["tag"] == current_tag_v:
        log(f"همگام هستیم — نیازی به آپدیت نیست", "OK")
        return 0
    
    log(f"نسخه جدید پیدا شد: {current_tag_v} → {upstream['tag']}", "WARN")
    
    # دانلود CodeFull.gs جدید
    try:
        new_codefull = fetch_upstream_codefull(upstream["tag"])
    except Exception as e:
        log(f"خطا در دانلود CodeFull.gs: {e}", "ERROR")
        return 1
    
    new_lines = len(new_codefull.splitlines())
    log(f"CodeFull.gs upstream دانلود شد ({new_lines} خط)")
    
    # ── چک: آیا CodeFull.gs واقعاً تغییر کرده؟ ──
    # بسیاری از release ها فقط شماره نسخه رو بالا می‌برن
    # (تغییرات در اپ Rust، نه در Apps Script)
    upstream_path = OUR_REPO_DIR / "CodeFull.gs.upstream"
    codefull_changed = True
    if upstream_path.exists():
        old_content = upstream_path.read_text()
        if old_content == new_codefull:
            codefull_changed = False
            log("CodeFull.gs بدون تغییر — فقط شماره نسخه آپدیت می‌شه", "INFO")
        else:
            # محاسبه تفاوت برای لاگ
            old_lines_count = len(old_content.splitlines())
            log(f"CodeFull.gs تغییر کرده: {old_lines_count} → {new_lines} خط", "OK")
    
    # آپدیت template (حتی اگه تغییر نکرده، باز بنویس — مهم نیست)
    if not update_template(new_codefull):
        return 1
    
    # آپدیت VERSION
    update_version_file(upstream["tag"], new_lines)
    
    # آپدیت HTML
    update_html_links(current_tag_v, upstream["tag"])
    
    # آپدیت README badge
    update_readme_badge(current_tag_v, upstream["tag"])
    
    # آپدیت CHANGELOG (با ذکر اینکه CodeFull تغییر کرد یا نه)
    upstream_body = upstream.get("body", "")
    if not codefull_changed:
        upstream_body = (
            "ℹ️ CodeFull.gs بدون تغییر نسبت به نسخه قبل — "
            "تغییرات این release فقط در اپ Rust (نه Apps Script).\n\n"
            + upstream_body
        )
    append_changelog(current_tag_v, upstream["tag"], upstream_body)
    
    if codefull_changed:
        log(f"sync کامل شد: {current_tag_v} → {upstream['tag']} (CodeFull.gs تغییر کرد)", "OK")
    else:
        log(f"sync کامل شد: {current_tag_v} → {upstream['tag']} (فقط شماره نسخه)", "OK")
    
    # خروجی برای GitHub Actions (تشخیص که آیا تغییر کرد)
    if "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a") as f:
            f.write(f"synced=true\n")
            f.write(f"old_version={current_tag}\n")
            f.write(f"new_version={upstream['tag'].lstrip('v')}\n")
            f.write(f"codefull_changed={'true' if codefull_changed else 'false'}\n")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
