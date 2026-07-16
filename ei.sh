#!/data/data/com.termux/files/usr/bin/bash

set -o pipefail

PACKAGE_PREFIX="free.no"
ROBLOX_URL="https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server"

# ============================================================
# CONFIG
# ============================================================
SCREENSHOT_INTERVAL=60
LAUNCH_DELAY=35
PID_TIMEOUT=60

DISCORD_WEBHOOK="https://discord.com/api/webhooks/1483451715104804964/o0vgYLS-zg4WUXHQM-GiaT0idCfzz-bqPAqRXi4ME0xjEQusxdA3zmEdRQIzUiHovOb3"
DISCORD_PING_USER=""

TMP_DIR="/data/data/com.termux/files/usr/tmp"
PID_FILE="${TMP_DIR}/roblox_bot.pid"
START_TIME_FILE="${TMP_DIR}/roblox_start_time"
MSG_FILE="${TMP_DIR}/roblox_msg.txt"

# ============================================================
# INIT PACKAGES
# ============================================================
init_packages() {
    PACKAGES=()
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && PACKAGES+=("$pkg")
    done < <(su -c "pm list packages" 2>/dev/null | grep "^package:${PACKAGE_PREFIX}" 2>/dev/null | sed 's/package://')
}

# ============================================================
# JSON ESCAPE — Pure bash, escape quote & real newlines only
# ============================================================
json_escape() {
    local input="$1"
    local output=""
    local i c
    for ((i=0; i<${#input}; i++)); do
        c="${input:$i:1}"
        case "$c" in
            '"')  output+='\\"' ;;
            $'\n') output+='\\n' ;;
            $'\r') output+='\\r' ;;
            $'\t') output+='\\t' ;;
            *)    output+="$c" ;;
        esac
    done
    printf '%s' "$output"
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

    local title_escaped desc_escaped
    title_escaped=$(json_escape "$title")
    desc_escaped=$(json_escape "$desc")

    if [[ -n "$img" && -f "$img" ]]; then
        local b="----BotBoundary$(date +%s)"
        {
            echo "--$b"
            echo 'Content-Disposition: form-data; name="payload_json"'
            echo 'Content-Type: application/json'
            echo ""
            echo "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title_escaped\",\"description\":\"$desc_escaped\",\"color\":$color,\"timestamp\":\"$ts\",\"footer\":{\"text\":\"Roblox Bot\"}}]}"
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
        curl -s -H "Content-Type: application/json" -X POST -d "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title_escaped\",\"description\":\"$desc_escaped\",\"color\":$color,\"timestamp\":\"$ts\",\"footer\":{\"text\":\"Roblox Bot\"}}]}" "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
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
    local start=0
    [[ -f "$START_TIME_FILE" ]] && start=$(cat "$START_TIME_FILE" 2>/dev/null | tr -d '[:space:]')
    [[ -z "$start" || ! "$start" =~ ^[0-9]+$ ]] && start=0
    local now=$(date +%s)
    local elapsed=$((now - start))
    format_duration "$elapsed"
}

# ============================================================
# GET PID — Retry (buat protect pas startup)
# ============================================================
get_pid_retry() {
    local pkg="$1"
    local pid=""
    local retries=0
    while [[ -z "$pid" && $retries -lt $PID_TIMEOUT ]]; do
        pid=$(su -c "pgrep -f '$pkg' 2>/dev/null" | head -1)
        [[ -z "$pid" ]] && sleep 1 && ((retries++))
    done
    echo "$pid"
}

# ============================================================
# PROTECT APP
# ============================================================
protect_app() {
    local pkg="$1"
    local pid=$(get_pid_retry "$pkg")
    if [[ -n "$pid" ]]; then
        su -c "echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null"
    else
        discord "⚠️ Warning" "Failed to get PID for \`$pkg\` after ${PID_TIMEOUT}s" 16776960
    fi
    su -c "cmd appops set $pkg RUN_IN_BACKGROUND allow 2>/dev/null"
    su -c "cmd deviceidle whitelist +$pkg 2>/dev/null"
}

# ============================================================
# BUILD MESSAGE — Pake printf ke file
# ============================================================
build_msg() {
    > "$MSG_FILE"

    local time_str=$(date "+%H:%M:%S")
    local uptime=$(get_uptime)

    printf "**⏰ Time:** \`%s\`\n" "$time_str" >> "$MSG_FILE"
    printf "**⏱️ Uptime:** \`%s\`\n\n" "$uptime" >> "$MSG_FILE"
    printf "📦 **Packages:**\n" >> "$MSG_FILE"

    for pkg in "${PACKAGES[@]}"; do
        local app_name="${pkg##*.}"
        local pid=$(su -c "pgrep -f '$pkg' 2>/dev/null" | head -1)
        if [[ -n "$pid" ]]; then
            printf "• 🟢 \`%s\` — PID: \`%s\`\n" "$app_name" "$pid" >> "$MSG_FILE"
        else
            printf "• 🔴 \`%s\` — PID: **TIMEOUT**\n" "$app_name" >> "$MSG_FILE"
        fi
    done

    cat "$MSG_FILE"
}

# ============================================================
# MAIN LOOP — Function biar bisa pake local
# ============================================================
main_loop() {
    while true; do
        local msg=$(build_msg)
        discord "📸 Screenshot" "$msg" 3447003 "$(ss)"
        sleep "$SCREENSHOT_INTERVAL"
    done
}

# ============================================================
# CLEANUP
# ============================================================
cleanup() {
    init_packages
    for pkg in "${PACKAGES[@]}"; do su -c "am force-stop $pkg 2>/dev/null"; done
    rm -f "$PID_FILE"
    rm -f "$START_TIME_FILE"
    rm -f "$MSG_FILE"
    rm -f "${TMP_DIR}"/rb_*.png 2>/dev/null
}

# ============================================================
# DAEMON MODE
# ============================================================
if [[ "$1" == "daemon" ]]; then
    echo $$ > "$PID_FILE"
    date +%s > "$START_TIME_FILE"
    > "$MSG_FILE"
    init_packages
    trap 'cleanup; exit 0' SIGTERM SIGINT

    [[ ${#PACKAGES[@]} -eq 0 ]] && { discord "❌ Error" "No packages found." 16711680; exit 1; }

    # Startup
    startup_msg="🚀 **Daemon Started**\n"
    startup_msg+="📦 Packages: ${#PACKAGES[@]}\n"
    for pkg in "${PACKAGES[@]}"; do
        startup_msg+="• \`$pkg\`\n"
    done
    startup_msg+="\n📸 **Screenshot every ${SCREENSHOT_INTERVAL}s**\n"
    startup_msg+="⏳ Launch delay: ${LAUNCH_DELAY}s between apps\n"
    startup_msg+="🛡️ PID timeout: ${PID_TIMEOUT}s"
    discord "🚀 RobloxBot Started" "$startup_msg" 3066993

    # Launch + protect
    i=0
    for pkg in "${PACKAGES[@]}"; do
        su -c "am start -a android.intent.action.VIEW -d '$ROBLOX_URL' -p $pkg" >/dev/null 2>&1
        protect_app "$pkg"
        (( i++ ))
        (( i < ${#PACKAGES[@]} )) && sleep "$LAUNCH_DELAY"
    done

    # Panggil loop function
    main_loop
    exit 0
fi

# ============================================================
# START
# ============================================================
if [[ "$1" == "start" ]]; then
    if [[ -f "$PID_FILE" ]]; then
        old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            discord "⚠️ Already Running" "Bot is already running.\nPID: $old_pid" 16776960
            exit 1
        fi
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
    uptime=$(get_uptime)
    stop_msg="🛑 **Bot Stopped**\n"
    stop_msg+="⏱️ Total uptime: \`$uptime\`\n"
    if [[ -f "$PID_FILE" ]]; then
        old_pid=$(cat "$PID_FILE")
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
    status_msg=""
    color=3447003
    has_timeout=0

    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        status_msg="🟢 **Bot Running**\n"
        status_msg+="🆔 Bot PID: $(cat $PID_FILE)\n\n"
        color=3066993
    else
        status_msg="🔴 **Bot Stopped**\n\n"
        color=16711680
    fi

    status_msg+="$(build_msg)"
    status_msg+="\n\n📸 **Screenshot:** every ${SCREENSHOT_INTERVAL}s\n"
    status_msg+="⏳ **Launch delay:** ${LAUNCH_DELAY}s\n"
    status_msg+="🛡️ **PID timeout:** ${PID_TIMEOUT}s"

    # Cek timeout
    while IFS=: read -r _ _ status; do
        [[ "$status" == "TIMEOUT" ]] && has_timeout=1
    done < "$MSG_FILE"

    if [[ $has_timeout -eq 1 ]]; then
        color=16776960
    fi

    discord "📊 Status + Screenshot" "$status_msg" $color "$(ss)"
    exit 0
fi

# ============================================================
# TEST WEBHOOK
# ============================================================
if [[ "$1" == "test-webhook" ]]; then
    [[ -z "$DISCORD_WEBHOOK" ]] && { discord "❌ Error" "No webhook configured" 16711680; exit 1; }
    discord "🧪 Test" "Webhook working! (local fix version)" 3447003
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
help_msg="🎮 **RobloxBot | LOCAL FIX**\n\n"
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
help_msg+="• Local fix: **main_loop function**\n"
help_msg+="• All output: Discord only"

discord "❓ Help" "$help_msg" 3447003