#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# AUTO-ROOT: Kalau belum root, re-execute dengan su
# ============================================================
if [[ $(id -u) -ne 0 ]]; then
    exec su -c "bash '$0' '$@'"
fi

set -o pipefail

PACKAGE_PREFIX="free.no"
ROBLOX_URL="https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server"

# ============================================================
# INTERVAL SETTINGS
# ============================================================
CHECK_INTERVAL=2          # Cek crash tiap 2 detik
UPDATE_INTERVAL=5         # Update downtime tiap 5 detik
PROTECT_INTERVAL=300      # Protect tiap 5 menit

DISCORD_WEBHOOK="https://discord.com/api/webhooks/1483451715104804964/o0vgYLS-zg4WUXHQM-GiaT0idCfzz-bqPAqRXi4ME0xjEQusxdA3zmEdRQIzUiHovOb3"
DISCORD_PING_USER=""

TMP_DIR="/data/data/com.termux/files/usr/tmp"
PID_FILE="${TMP_DIR}/roblox_bot.pid"
STATE_FILE="${TMP_DIR}/roblox_state.db"

ALLOWED_PKGS=("com.termux" "$PACKAGE_PREFIX")

# ============================================================
# INIT PACKAGES
# ============================================================
init_packages() {
    PACKAGES=()
    while IFS= read -r pkg; do PACKAGES+=("$pkg"); done < <(pm list packages 2>/dev/null | grep "^package:${PACKAGE_PREFIX}" 2>/dev/null | sed 's/package://')
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
    screencap -p "$p" 2>/dev/null
    [[ -f "$p" ]] && echo "$p" || echo ""
}

# ============================================================
# SQLITE STATE DB
# ============================================================
db() { sqlite3 "$STATE_FILE" "$1" 2>/dev/null; }
init_db() { [[ -f "$STATE_FILE" ]] || db "CREATE TABLE state(key TEXT PRIMARY KEY, value TEXT);"; }
get() { db "SELECT value FROM state WHERE key='$1';" || echo ""; }
set() { db "INSERT OR REPLACE INTO state(key,value) VALUES('$1','$2');"; }

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
# CHECK APP ALIVE
# ============================================================
alive() {
    local pkg="$1"
    local pid

    pid=$(pidof "$pkg" 2>/dev/null)
    [[ -z "$pid" ]] && pid=$(pgrep -f "^$pkg" 2>/dev/null | head -1)
    [[ -z "$pid" ]] && return 1

    [[ -d "/proc/$pid" ]] || return 1

    local st=$(awk '{print $3}' /proc/$pid/stat 2>/dev/null)
    [[ "$st" == "Z" ]] && return 1

    return 0
}

# ============================================================
# LAUNCH APP
# ============================================================
launch() {
    local pkg="$1" name="$2"
    alive "$pkg" && return 0
    am start -a android.intent.action.VIEW -d "$ROBLOX_URL" -p "$pkg" >/dev/null 2>&1
}

# ============================================================
# PROTECT APP
# ============================================================
protect_app() {
    local pkg="$1"
    local now=$(date +%s)
    local last_prot=$(get "protected_${pkg}_time")
    [[ -n "$last_prot" && $((now - last_prot)) -lt $PROTECT_INTERVAL ]] && return 0

    local pid=$(pidof "$pkg" 2>/dev/null || pgrep -f "^$pkg" 2>/dev/null | head -1)
    [[ -z "$pid" ]] && return

    echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null
    chrt -f -p 99 "$pid" 2>/dev/null
    cmd appops set "$pkg" RUN_IN_BACKGROUND allow 2>/dev/null
    cmd deviceidle whitelist +"$pkg" 2>/dev/null

    set "protected_${pkg}_time" "$now"
}

# ============================================================
# KILL UNWANTED APPS — SEKALI PAS START
# ============================================================
kill_unwanted() {
    local to_kill=()
    local pkg
    while IFS= read -r pkg; do
        pkg="${pkg#package:}"
        local allowed=0
        for a in "${ALLOWED_PKGS[@]}"; do
            [[ "$pkg" == "$a"* ]] && { allowed=1; break; }
        done
        [[ $allowed -eq 0 ]] && to_kill+=("$pkg")
    done < <(pm list packages -3 2>/dev/null)

    local i=0
    for pkg in "${to_kill[@]}"; do
        am force-stop "$pkg" 2>/dev/null
        (( i++ ))
        [[ $((i % 3)) -eq 0 ]] && sleep 0.2
    done
}

# ============================================================
# CHECK CRASH
# ============================================================
check_crash() {
    local pkg="$1" name="$2"
    local now=$(date +%s)
    local crash_time=$(get "crash_time_$pkg")
    local ss_sent=$(get "crash_ss_$pkg")
    local last_update=$(get "crash_update_$pkg")

    # APP HIDUP
    if alive "$pkg"; then
        if [[ -n "$crash_time" ]]; then
            local downtime=$((now - crash_time))
            local downtime_str=$(format_duration "$downtime")
            discord "✅ Recovered" "**$name** is back online!\nPackage: \`$pkg\`\nTotal downtime: **$downtime_str**" 3066993
            set "crash_time_$pkg" ""
            set "crash_ss_$pkg" ""
            set "crash_update_$pkg" ""
        fi
        return 0
    fi

    # APP MATI
    if [[ -z "$crash_time" ]]; then
        set "crash_time_$pkg" "$now"
        crash_time="$now"
    fi

    local downtime=$((now - crash_time))
    local downtime_str=$(format_duration "$downtime")

    if [[ -z "$ss_sent" ]]; then
        discord "💀 Crash Detected" "**$name** has crashed!\nPackage: \`$pkg\`\nDowntime: **$downtime_str**" 16711680 "$(ss)"
        set "crash_ss_$pkg" "1"
        set "crash_update_$pkg" "$now"
        return 0
    fi

    if [[ -n "$last_update" && $((now - last_update)) -lt $UPDATE_INTERVAL ]]; then
        return 0
    fi

    discord "💀 Still Down" "**$name** is still crashed.\nPackage: \`$pkg\`\nDowntime: **$downtime_str**" 16711680
    set "crash_update_$pkg" "$now"
}

# ============================================================
# CLEANUP
# ============================================================
cleanup() {
    init_packages
    for pkg in "${PACKAGES[@]}"; do am force-stop "$pkg" 2>/dev/null; done
    rm -f "$PID_FILE"
    rm -f "${TMP_DIR}"/rb_*.png 2>/dev/null
}

# ============================================================
# DAEMON MODE
# ============================================================
if [[ "$1" == "daemon" ]]; then
    echo $$ > "$PID_FILE"
    init_db
    init_packages
    trap 'cleanup; exit 0' SIGTERM SIGINT

    [[ ${#PACKAGES[@]} -eq 0 ]] && { discord "❌ Error" "No packages found." 16711680; exit 1; }

    local startup_msg="🚀 **Daemon Started**\n"
    startup_msg+="📦 Packages: ${#PACKAGES[@]}\n"
    for pkg in "${PACKAGES[@]}"; do
        startup_msg+="• \`$pkg\`\n"
    done
    startup_msg+="\n⏱️ **Intervals:**\n"
    startup_msg+="• ⚡ Crash check: ${CHECK_INTERVAL}s\n"
    startup_msg+="• 📊 Downtime update: ${UPDATE_INTERVAL}s\n"
    startup_msg+="• 🔒 Protect: ${PROTECT_INTERVAL}s\n\n"
    startup_msg+="⚠️ **Auto-restart: DISABLED**\n"
    startup_msg+="Crash = notif + screenshot (1x) + downtime tracking."
    discord "🚀 RobloxBot Started" "$startup_msg" 3066993

    for pkg in "${PACKAGES[@]}"; do
        am force-stop "$pkg" 2>/dev/null
    done
    sleep 2

    local i=0
    for pkg in "${PACKAGES[@]}"; do
        launch "$pkg" "${pkg##*.}"
        (( i++ )); (( i < ${#PACKAGES[@]} )) && sleep 30
    done

    while true; do
        for pkg in "${PACKAGES[@]}"; do
            check_crash "$pkg" "${pkg##*.}"
            protect_app "$pkg"
        done

        sleep "$CHECK_INTERVAL"
    done
    exit 0
fi

# ============================================================
# START
# ============================================================
if [[ "$1" == "start" ]]; then
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        discord "⚠️ Already Running" "Bot is already running.\nPID: $(cat $PID_FILE)" 16776960
        exit 1
    fi

    init_packages
    kill_unwanted

    nohup bash "$0" daemon >/dev/null 2>&1 &
    sleep 1
    if [[ -f "$PID_FILE" ]]; then
        discord "✅ Started" "Bot daemon started.\nPID: $(cat $PID_FILE)\n\n⚡ Crash check: ${CHECK_INTERVAL}s\n📊 Downtime update: ${UPDATE_INTERVAL}s\n🔒 Protect: ${PROTECT_INTERVAL}s\n\n⚠️ Auto-restart: DISABLED" 3066993
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
    local stop_msg="🛑 **Bot Stopped**\n"
    if [[ -f "$PID_FILE" ]]; then
        local old_pid=$(cat "$PID_FILE")
        kill "$old_pid" 2>/dev/null
        sleep 1
        kill -9 "$old_pid" 2>/dev/null
        stop_msg+="• Killed PID: $old_pid\n"
    fi
    cleanup
    stop_msg+="• All Roblox packages stopped\n"
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

    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        status_msg="🟢 **Running**\n"
        status_msg+="🆔 PID: $(cat $PID_FILE)\n\n"
        color=3066993
    else
        status_msg="🔴 **Stopped**\n\n"
        color=16711680
    fi

    status_msg+="⏱️ **Intervals:**\n"
    status_msg+="• ⚡ Crash check: ${CHECK_INTERVAL}s\n"
    status_msg+="• 📊 Downtime update: ${UPDATE_INTERVAL}s\n"
    status_msg+="• 🔒 Protect: ${PROTECT_INTERVAL}s\n\n"

    status_msg+="⚠️ **Auto-restart: DISABLED**\n\n"

    status_msg+="📦 **Packages (${#PACKAGES[@]}):**\n"
    for pkg in "${PACKAGES[@]}"; do
        local name="${pkg##*.}"
        if alive "$pkg"; then
            status_msg+="• 🟢 \`$name\` — $pkg\n"
        else
            status_msg+="• 🔴 \`$name\` — $pkg\n"
        fi
    done

    discord "📊 Status" "$status_msg" $color
    exit 0
fi

# ============================================================
# TEST WEBHOOK
# ============================================================
if [[ "$1" == "test-webhook" ]]; then
    [[ -z "$DISCORD_WEBHOOK" ]] && { discord "❌ Error" "No webhook configured" 16711680; exit 1; }
    discord "🧪 Test" "Webhook working! (Super Minimal)" 3447003
    exit 0
fi

# ============================================================
# TEST SCREENSHOT
# ============================================================
if [[ "$1" == "test-screenshot" ]]; then
    local s
    s=$(ss)
    if [[ -n "$s" ]]; then
        discord "🧪 Screenshot Test" "Screenshot captured and sent." 3447003 "$s"
    else
        discord "❌ Failed" "Failed to capture screenshot." 16711680
    fi
    exit 0
fi

# ============================================================
# RESET STATE
# ============================================================
if [[ "$1" == "reset-state" ]]; then
    rm -f "$STATE_FILE"
    rm -f "${TMP_DIR}"/rb_*.png 2>/dev/null
    discord "🔄 Reset" "State DB and temp files reset successfully." 3447003
    exit 0
fi

# ============================================================
# HELP
# ============================================================
help_msg="🎮 **RobloxBot | SUPER MINIMAL**

"
help_msg+="**Usage:**\n"
help_msg+="\`./roblox_bot.sh start\` — Start daemon (auto-root)\n"
help_msg+="\`./roblox_bot.sh stop\` — Stop daemon\n"
help_msg+="\`./roblox_bot.sh restart\` — Restart daemon\n"
help_msg+="\`./roblox_bot.sh status\` — Check status (Discord)\n"
help_msg+="\`./roblox_bot.sh test-webhook\` — Test webhook\n"
help_msg+="\`./roblox_bot.sh test-screenshot\` — Test screenshot\n"
help_msg+="\`./roblox_bot.sh reset-state\` — Reset state DB\n\n"
help_msg+="**⏱️ Intervals:**\n"
help_msg+="• Crash check: ${CHECK_INTERVAL}s\n"
help_msg+="• Downtime update: ${UPDATE_INTERVAL}s\n"
help_msg+="• Protect: ${PROTECT_INTERVAL}s\n\n"
help_msg+="**🔒 Features:**\n"
help_msg+="• Auto-restart: **DISABLED**\n"
help_msg+="• Screenshot: **1x per crash**\n"
help_msg+="• Downtime: tracked & updated\n"
help_msg+="• Kill unwanted: **ONCE at start**\n"
help_msg+="• No cache clear (Android handles it)\n"
help_msg+="• No heavy lock (protect is fast)\n"
help_msg+="• Root optimized: no su overhead\n"
help_msg+="• Auto-root: runs as root automatically\n"
help_msg+="• All output: Discord only"

discord "❓ Help" "$help_msg" 3447003