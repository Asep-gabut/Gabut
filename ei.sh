#!/data/data/com.termux/files/usr/bin/bash

set -o pipefail

PACKAGE_PREFIX="free.no"
ROBLOX_URL="https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server"

# ============================================================
# INTERVAL SETTINGS
# ============================================================
SCREENSHOT_INTERVAL=60     # Kirim SS tiap 60 detik (1 menit)
LAUNCH_DELAY=35              # Delay antar launch (detik)
PID_TIMEOUT=60               # Max tunggu PID (detik)

DISCORD_WEBHOOK="https://discord.com/api/webhooks/1483451715104804964/o0vgYLS-zg4WUXHQM-GiaT0idCfzz-bqPAqRXi4ME0xjEQusxdA3zmEdRQIzUiHovOb3"
DISCORD_PING_USER=""

TMP_DIR="/data/data/com.termux/files/usr/tmp"
PID_FILE="${TMP_DIR}/roblox_bot.pid"
START_TIME_FILE="${TMP_DIR}/roblox_start_time"

# ============================================================
# INIT PACKAGES
# ============================================================
init_packages() {
    PACKAGES=()
    while IFS= read -r pkg; do PACKAGES+=("$pkg"); done < <(su -c "pm list packages" 2>/dev/null | grep "^package:${PACKAGE_PREFIX}" 2>/dev/null | sed 's/package://')
}

# ============================================================
# DISCORD — ORIGINAL PROVEN LOGIC
# ============================================================
discord() {
    local title="$1" desc="$2" color="${3:-3447003}" img="$4"
    [[ -z "$DISCORD_WEBHOOK" ]] && return

    local ping=""
    [[ -n "$DISCORD_PING_USER" ]] && ping="<@$DISCORD_PING_USER> "

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [[ -n "$img" && -f "$img" ]]; then
        local b="----BotBoundary$(date +%s)"
        {
            echo "--$b"
            echo 'Content-Disposition: form-data; name="payload_json"'
            echo 'Content-Type: application/json'
            echo ""
            echo "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$desc\",\"color\":$color,\"timestamp\":\"$ts\",\"footer\":{\"text\":\"Roblox Bot\"}}]}"
            echo "--$b"
            echo 'Content-Disposition: form-data; name="file"; filename="screenshot.png"'
            echo 'Content-Type: image/png'
            echo ""
            cat "$img"
            echo ""
            echo "--$b--"
        } | curl -s -X POST -H "Content-Type: multipart/form-data; boundary=$b" --data-binary @- "$DISCORD_WEBHOOK" >/dev/null 2>&1

        rm -f "$img"
    else
        curl -s -H "Content-Type: application/json" -X POST -d "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$desc\",\"color\":$color,\"timestamp\":\"$ts\",\"footer\":{\"text\":\"Roblox Bot\"}}]}" "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
    fi
}

# ============================================================
# SCREENSHOT — ORIGINAL PROVEN LOGIC
# ============================================================
ss() {
    local p="${TMP_DIR}/rb_$(date +%s)_$$.png"
    su -c "screencap -p $p" 2>/dev/null
    [[ -f "$p" ]] && echo "$p" || echo ""
}

# ============================================================
# FORMAT DURATION — ORIGINAL PROVEN LOGIC
# ============================================================
format_duration() {
    local seconds="$1"
    local h=$((seconds / 3600))
    local m=$(((seconds % 3600) / 60))
    local s=$((seconds % 60))
    local result=""
    [[ $h -gt 0 ]] && result+="${h}h "
    [[ $m -gt 0 ]] && result+="${m}m "
    result+="${s}s"
    echo "$result"
}

# ============================================================
# GET UPTIME
# ============================================================
get_uptime() {
    if [[ -f "$START_TIME_FILE" ]]; then
        local start=$(cat "$START_TIME_FILE")
        local now=$(date +%s)
        local elapsed=$((now - start))
        format_duration "$elapsed"
    else
        echo "Unknown"
    fi
}

# ============================================================
# GET PID STATUS — Cek PID dengan retry (sama kayak protect)
# ============================================================
get_pid_status() {
    local pkg="$1"
    local pid=""
    local retries=0

    while [[ -z "$pid" && $retries -lt $PID_TIMEOUT ]]; do
        pid=$(su -c "pgrep -f '$pkg' 2>/dev/null" | head -1)
        [[ -z "$pid" ]] && sleep 1 && ((retries++))
    done

    if [[ -n "$pid" ]]; then
        echo "PID:$pid"
    else
        echo "TIMEOUT"
    fi
}

# ============================================================
# PROTECT APP — Sekali pas launch, retry PID max PID_TIMEOUT
# ============================================================
protect_app() {
    local pkg="$1"
    local status=$(get_pid_status "$pkg")

    if [[ "$status" == "TIMEOUT" ]]; then
        discord "⚠️ Warning" "Failed to get PID for \`$pkg\` after ${PID_TIMEOUT}s" 16776960
    else
        local pid="${status#PID:}"
        su -c "echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null"
    fi

    su -c "cmd appops set $pkg RUN_IN_BACKGROUND allow 2>/dev/null"
    su -c "cmd deviceidle whitelist +$pkg 2>/dev/null"
}

# ============================================================
# CLEANUP
# ============================================================
cleanup() {
    init_packages
    for pkg in "${PACKAGES[@]}"; do su -c "am force-stop $pkg 2>/dev/null"; done
    rm -f "$PID_FILE"
    rm -f "$START_TIME_FILE"
    rm -f "${TMP_DIR}"/rb_*.png 2>/dev/null
}

# ============================================================
# DAEMON MODE — Screenshot tiap menit + status
# ============================================================
if [[ "$1" == "daemon" ]]; then
    echo $$ > "$PID_FILE"
    date +%s > "$START_TIME_FILE"
    init_packages
    trap 'cleanup; exit 0' SIGTERM SIGINT

    [[ ${#PACKAGES[@]} -eq 0 ]] && { discord "❌ Error" "No packages found." 16711680; exit 1; }

    # Startup notification
    local startup_msg="🚀 **Daemon Started**\n"
    startup_msg+="📦 Packages: ${#PACKAGES[@]}\n"
    for pkg in "${PACKAGES[@]}"; do
        startup_msg+="• \`$pkg\`\n"
    done
    startup_msg+="\n📸 **Screenshot every ${SCREENSHOT_INTERVAL}s**\n"
    startup_msg+="🔴 Crash detection: **DISABLED**\n"
    startup_msg+="⏳ Launch delay: ${LAUNCH_DELAY}s between apps\n"
    startup_msg+="🛡️ PID timeout: ${PID_TIMEOUT}s"
    discord "🚀 RobloxBot Started" "$startup_msg" 3066993

    # Launch + protect dengan delay antar app
    local i=0
    for pkg in "${PACKAGES[@]}"; do
        su -c "am start -a android.intent.action.VIEW -d '$ROBLOX_URL' -p $pkg" >/dev/null 2>&1
        protect_app "$pkg"
        (( i++ ))
        (( i < ${#PACKAGES[@]} )) && sleep "$LAUNCH_DELAY"
    done

    local last_screenshot=0

    # LOOP UTAMA — Cuma screenshot + sleep
    while true; do
        local now=$(date +%s)

        # Screenshot tiap 1 menit
        if [[ $((now - last_screenshot)) -ge $SCREENSHOT_INTERVAL ]]; then
            local time_str=$(date "+%H:%M:%S")
            local uptime=$(get_uptime)
            discord "📸 Screenshot" "**Time:** \`$time_str\`\n**⏱️ Uptime:** \`$uptime\`\nAuto-capture every ${SCREENSHOT_INTERVAL}s" 3447003 "$(ss)"
            last_screenshot=$now
        fi

        sleep 5
    done
    exit 0
fi

# ============================================================
# START
# ============================================================
if [[ "$1" == "start" ]]; then
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        local uptime=$(get_uptime)
        discord "⚠️ Already Running" "Bot is already running.\nPID: $(cat $PID_FILE)\n⏱️ Uptime: \`$uptime\`" 16776960
        exit 1
    fi
    nohup bash "$0" daemon >/dev/null 2>&1 &
    sleep 1
    if [[ -f "$PID_FILE" ]]; then
        discord "✅ Started" "Bot daemon started.\nPID: $(cat $PID_FILE)\n\n📸 Screenshot: every ${SCREENSHOT_INTERVAL}s\n🔴 Crash detect: DISABLED" 3066993
    else
        discord "❌ Failed" "Failed to start daemon." 16711680
    fi
    exit 0
fi

# ============================================================
# STOP
# ============================================================
if [[ "$1" == "stop" ]]; then
    init_packages
    local uptime=$(get_uptime)
    local stop_msg="🛑 **Bot Stopped**\n"
    stop_msg+="⏱️ Total uptime: \`$uptime\`\n"
    if [[ -f "$PID_FILE" ]]; then
        local old_pid=$(cat "$PID_FILE")
        kill "$old_pid" 2>/dev/null
        sleep 1
        kill -9 "$old_pid" 2>/dev/null
        stop_msg+="• Killed PID: $old_pid\n"
    fi
    cleanup
    stop_msg+="• Daemon stopped\n"
    stop_msg+="• Temp files cleaned"
    discord "🛑 Stopped" "$stop_msg" 16711680
    exit 0
fi

# ============================================================
# RESTART
# ============================================================
if [[ "$1" == "restart" ]]; then
    bash "$0" stop
    sleep 2
    bash "$0" start
    exit 0
fi

# ============================================================
# STATUS — Gabung screenshot + PID status jelas
# ============================================================
if [[ "$1" == "status" ]]; then
    init_packages
    local status_msg=""
    local color=3447003
    local uptime=$(get_uptime)
    local has_timeout=0

    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        status_msg="🟢 **Bot Running**\n"
        status_msg+="🆔 Bot PID: $(cat $PID_FILE)\n"
        status_msg+="⏱️ Uptime: \`$uptime\`\n\n"
        color=3066993
    else
        status_msg="🔴 **Bot Stopped**\n\n"
        color=16711680
    fi

    status_msg+="📦 **Packages (${#PACKAGES[@]}):**\n"
    for pkg in "${PACKAGES[@]}"; do
        local app_name="${pkg##*.}"
        local pid_status=$(get_pid_status "$pkg")

        if [[ "$pid_status" == "TIMEOUT" ]]; then
            status_msg+="• 🟡 \`$app_name\` — PID: **TIMEOUT** (not found after ${PID_TIMEOUT}s)\n"
            has_timeout=1
        else
            local pid="${pid_status#PID:}"
            status_msg+="• 🟢 \`$app_name\` — PID: \`$pid\`\n"
        fi
    done

    status_msg+="\n📸 **Screenshot:** every ${SCREENSHOT_INTERVAL}s\n"
    status_msg+="🔴 **Crash detect:** DISABLED\n"
    status_msg+="⏳ **Launch delay:** ${LAUNCH_DELAY}s\n"
    status_msg+="🛡️ **PID timeout:** ${PID_TIMEOUT}s"

    # Kalau ada timeout, warn kuning
    if [[ $has_timeout -eq 1 ]]; then
        color=16776960
    fi

    # Kirim status + screenshot dalam satu embed
    discord "📊 Status + Screenshot" "$status_msg" $color "$(ss)"
    exit 0
fi

# ============================================================
# TEST WEBHOOK
# ============================================================
if [[ "$1" == "test-webhook" ]]; then
    [[ -z "$DISCORD_WEBHOOK" ]] && { discord "❌ Error" "No webhook configured" 16711680; exit 1; }
    discord "🧪 Test" "Webhook working! (Status + Screenshot version)" 3447003
    exit 0
fi

# ============================================================
# TEST SCREENSHOT
# ============================================================
if [[ "$1" == "test-screenshot" ]]; then
    discord "🧪 Screenshot Test" "Testing screenshot with proven logic." 3447003 "$(ss)"
    exit 0
fi

# ============================================================
# HELP
# ============================================================
help_msg="🎮 **RobloxBot | STATUS + SCREENSHOT**\n\n"
help_msg+="**Usage:**\n"
help_msg+="\`start\` — Start daemon\n"
help_msg+="\`stop\` — Stop daemon & kill Roblox\n"
help_msg+="\`restart\` — Restart daemon\n"
help_msg+="\`status\` — Status + screenshot + PID info\n"
help_msg+="\`test-webhook\` — Test Discord webhook\n"
help_msg+="\`test-screenshot\` — Test screenshot\n\n"
help_msg+="**⏱️ Intervals:**\n"
help_msg+="• 📸 Screenshot: every ${SCREENSHOT_INTERVAL}s\n"
help_msg+="• ⏳ Launch delay: ${LAUNCH_DELAY}s between apps\n"
help_msg+="• 🛡️ PID timeout: ${PID_TIMEOUT}s\n\n"
help_msg+="**🔒 Features:**\n"
help_msg+="• Crash detection: **DISABLED**\n"
help_msg+="• Screenshot: **auto every ${SCREENSHOT_INTERVAL}s**\n"
help_msg+="• Status: **includes screenshot + PID status**\n"
help_msg+="• All output: Discord only"

discord "❓ Help" "$help_msg" 3447003