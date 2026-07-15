#!/data/data/com.termux/files/usr/bin/bash

set -o pipefail

PACKAGE_PREFIX="free.no"
ROBLOX_URL="https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server"

# ============================================================
# INTERVAL SETTINGS
# ============================================================
SCREENSHOT_INTERVAL=60     # Kirim SS tiap 60 detik (1 menit)
PROTECT_INTERVAL=300         # Protect app tiap 5 menit
LAUNCH_DELAY=35              # Delay antar launch (detik)

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
# DISCORD
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
# SCREENSHOT
# ============================================================
ss() {
    local p="${TMP_DIR}/rb_$(date +%s)_$$.png"
    su -c "screencap -p $p" 2>/dev/null
    [[ -f "$p" ]] && echo "$p" || echo ""
}

# ============================================================
# FORMAT DURATION
# ============================================================
format_duration() {
    local seconds="$1"
    local d=$((seconds / 86400))
    local h=$(((seconds % 86400) / 3600))
    local m=$(((seconds % 3600) / 60))
    local s=$((seconds % 60))
    local result=""
    [[ $d -gt 0 ]] && result+="${d}d "
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
# PROTECT APP — Ringan, cuma tiap 5 menit
# ============================================================
protect_app() {
    local pkg="$1"
    local now=$(date +%s)
    local last_prot_file="${TMP_DIR}/protected_${pkg}_time"

    if [[ -f "$last_prot_file" ]]; then
        local last_prot=$(cat "$last_prot_file")
        [[ $((now - last_prot)) -lt $PROTECT_INTERVAL ]] && return 0
    fi

    local pid=$(su -c "pgrep -f '$pkg' 2>/dev/null" | head -1)
    [[ -z "$pid" ]] && return
    su -c "echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null"
    su -c "cmd appops set $pkg RUN_IN_BACKGROUND allow 2>/dev/null"
    su -c "cmd deviceidle whitelist +$pkg 2>/dev/null"
    echo "$now" > "$last_prot_file"
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
    rm -f "${TMP_DIR}"/protected_*_time 2>/dev/null
}

# ============================================================
# DAEMON MODE — Screenshot tiap menit + uptime tracking
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
    startup_msg+="🛡️ OOM protect: every ${PROTECT_INTERVAL}s\n"
    startup_msg+="⏳ Launch delay: ${LAUNCH_DELAY}s between apps"
    discord "🚀 RobloxBot Started" "$startup_msg" 3066993

    # Launch dengan delay antar app
    local i=0
    for pkg in "${PACKAGES[@]}"; do
        su -c "am start -a android.intent.action.VIEW -d '$ROBLOX_URL' -p $pkg" >/dev/null 2>&1
        (( i++ ))
        (( i < ${#PACKAGES[@]} )) && sleep "$LAUNCH_DELAY"
    done

    local last_protect=0
    local last_screenshot=0

    # LOOP UTAMA — Ringan banget
    while true; do
        local now=$(date +%s)

        # 1. Protect app tiap 5 menit
        if [[ $((now - last_protect)) -ge $PROTECT_INTERVAL ]]; then
            for pkg in "${PACKAGES[@]}"; do
                protect_app "$pkg"
            done
            last_protect=$now
        fi

        # 2. Screenshot tiap 1 menit
        if [[ $((now - last_screenshot)) -ge $SCREENSHOT_INTERVAL ]]; then
            local s
            s=$(ss)
            if [[ -n "$s" ]]; then
                local time_str=$(date "+%H:%M:%S")
                local uptime=$(get_uptime)
                discord "📸 Screenshot" "**Time:** \`$time_str\`\n**⏱️ Uptime:** \`$uptime\`\nAuto-capture every ${SCREENSHOT_INTERVAL}s" 3447003 "$s"
            fi
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
# STATUS
# ============================================================
if [[ "$1" == "status" ]]; then
    init_packages
    local status_msg=""
    local color=3447003
    local uptime=$(get_uptime)

    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        status_msg="🟢 **Running**\n"
        status_msg+="🆔 PID: $(cat $PID_FILE)\n"
        status_msg+="⏱️ Uptime: \`$uptime\`\n\n"
        color=3066993
    else
        status_msg="🔴 **Stopped**\n\n"
        color=16711680
    fi

    status_msg+="📸 **Screenshot:** every ${SCREENSHOT_INTERVAL}s\n"
    status_msg+="🔴 **Crash detect:** DISABLED\n"
    status_msg+="🛡️ **OOM protect:** every ${PROTECT_INTERVAL}s\n"
    status_msg+="⏳ **Launch delay:** ${LAUNCH_DELAY}s\n\n"

    status_msg+="📦 **Packages (${#PACKAGES[@]}):**\n"
    for pkg in "${PACKAGES[@]}"; do
        status_msg+="• \`${pkg##*.}\` — $pkg\n"
    done

    discord "📊 Status" "$status_msg" $color
    exit 0
fi

# ============================================================
# TEST WEBHOOK
# ============================================================
if [[ "$1" == "test-webhook" ]]; then
    [[ -z "$DISCORD_WEBHOOK" ]] && { discord "❌ Error" "No webhook configured" 16711680; exit 1; }
    discord "🧪 Test" "Webhook working! (Lightweight + Uptime version)" 3447003
    exit 0
fi

# ============================================================
# TEST SCREENSHOT
# ============================================================
if [[ "$1" == "test-screenshot" ]]; then
    local s
    s=$(ss)
    if [[ -n "$s" ]]; then
        local uptime=$(get_uptime)
        discord "🧪 Screenshot Test" "Screenshot captured.\n⏱️ Uptime: \`$uptime\`" 3447003 "$s"
    else
        discord "❌ Failed" "Failed to capture screenshot." 16711680
    fi
    exit 0
fi

# ============================================================
# HELP
# ============================================================
help_msg="🎮 **RobloxBot | LIGHTWEIGHT + UPTIME**\n\n"
help_msg+="**Usage:**\n"
help_msg+="\`start\` — Start daemon\n"
help_msg+="\`stop\` — Stop daemon & kill Roblox\n"
help_msg+="\`restart\` — Restart daemon\n"
help_msg+="\`status\` — Check status + uptime\n"
help_msg+="\`test-webhook\` — Test Discord webhook\n"
help_msg+="\`test-screenshot\` — Test screenshot\n\n"
help_msg+="**⏱️ Intervals:**\n"
help_msg+="• 📸 Screenshot: every ${SCREENSHOT_INTERVAL}s\n"
help_msg+="• 🛡️ OOM protect: every ${PROTECT_INTERVAL}s\n"
help_msg+="• ⏳ Launch delay: ${LAUNCH_DELAY}s between apps\n\n"
help_msg+="**🔒 Features:**\n"
help_msg+="• Crash detection: **DISABLED**\n"
help_msg+="• Screenshot: **auto every ${SCREENSHOT_INTERVAL}s**\n"
help_msg+="• Uptime tracking: **enabled**\n"
help_msg+="• All output: Discord only"

discord "❓ Help" "$help_msg" 3447003