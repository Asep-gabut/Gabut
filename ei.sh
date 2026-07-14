#!/data/data/com.termux/files/usr/bin/bash

set -o pipefail

PACKAGE_PREFIX="free.no"
ROBLOX_URL="https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server"

# ============================================================
# INTERVAL SETTINGS — SIMPLE (cuma 3)
# ============================================================
CHECK_INTERVAL=2          # Cek crash tiap 2 detik (RINGAN)
HEAVY_INTERVAL=200           # Heavy task tiap 1 menit (BERAT)
UPDATE_INTERVAL=5          # Update downtime tiap 30 detik

# Internal intervals (nggak perlu diubah, cuma timestamp-based)
KILL_INTERVAL=120           # Kill unwanted tiap 2 menit (internal)
CACHE_INTERVAL=600          # Clear cache tiap 10 menit (internal)
PROTECT_INTERVAL=300        # Protect tiap 5 menit (internal)

DISCORD_WEBHOOK="https://discord.com/api/webhooks/1483451715104804964/o0vgYLS-zg4WUXHQM-GiaT0idCfzz-bqPAqRXi4ME0xjEQusxdA3zmEdRQIzUiHovOb3"
DISCORD_PING_USER=""

TMP_DIR="/data/data/com.termux/files/usr/tmp"
PID_FILE="${TMP_DIR}/roblox_bot.pid"
STATE_FILE="${TMP_DIR}/roblox_state.db"
HEAVY_LOCK="${TMP_DIR}/heavy.lock"

ALLOWED_PKGS=("com.termux" "$PACKAGE_PREFIX")

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
# SQLITE STATE DB
# ============================================================
db() { su -c "sqlite3 $STATE_FILE '$1' 2>/dev/null"; }
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
# CHECK APP ALIVE — ANTI FALSE DETECT
# ============================================================
alive() {
    local pkg="$1"
    local pid

    pid=$(su -c "pgrep -x '$pkg' 2>/dev/null" | head -1)
    [[ -z "$pid" ]] && pid=$(su -c "pgrep -f '$pkg' 2>/dev/null" | head -1)
    [[ -z "$pid" ]] && return 1

    [[ -d "/proc/$pid" ]] || return 1

    local st=$(su -c "cat /proc/$pid/stat 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
    [[ "$st" == "Z" ]] && return 1

    su -c "dumpsys window windows 2>/dev/null | grep -q '$pkg'" 2>/dev/null && return 0
    su -c "dumpsys activity activities 2>/dev/null | grep -m1 -E '$pkg.*(Resumed|Paused|Stopped)'" >/dev/null 2>&1 && return 0

    return 0
}

# ============================================================
# LAUNCH APP — Cuma sekali di awal
# ============================================================
launch() {
    local pkg="$1" name="$2"
    alive "$pkg" && return 0
    su -c "am start -a android.intent.action.VIEW -d '$ROBLOX_URL' -p $pkg" >/dev/null 2>&1
}

# ============================================================
# CLEAR CACHE — GENTLE
# ============================================================
clear_cache() {
    local pkg="$1"
    su -c "nice -n 19 ionice -c 3 find /data/data/$pkg -maxdepth 2 -type d \( -name 'cache' -o -name 'code_cache' \) 2>/dev/null | while read d; do
        case \"\$d\" in
            *session*|*auth*|*login*) continue ;;
        esac
        rm -rf \"\$d\"/* 2>/dev/null
        sleep 0.2
    done" 2>/dev/null
}

# ============================================================
# PROTECT APP — GENTLE (dengan jeda)
# ============================================================
protect_app() {
    local pkg="$1"
    local now=$(date +%s)
    local last_prot=$(get "protected_${pkg}_time")
    if [[ -n "$last_prot" && $((now - last_prot)) -lt $PROTECT_INTERVAL ]]; then
        return 0
    fi
    local pid=$(su -c "pgrep -f '$pkg' 2>/dev/null" | head -1)
    [[ -z "$pid" ]] && return
    su -c "echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null"
    sleep 0.2
    su -c "chrt -f -p 99 $pid 2>/dev/null"
    sleep 0.2
    su -c "cmd appops set $pkg RUN_IN_BACKGROUND allow 2>/dev/null"
    sleep 0.2
    su -c "cmd deviceidle whitelist +$pkg 2>/dev/null"
    set "protected_${pkg}_time" "$now"
}

# ============================================================
# KILL UNWANTED APPS — GENTLE (dengan jeda)
# ============================================================
kill_unwanted() {
    local now=$(date +%s)
    local last_kill=$(get "kill_unwanted_time")
    [[ -n "$last_kill" && $((now - last_kill)) -lt $KILL_INTERVAL ]] && return
    local pkg
    while IFS= read -r pkg; do
        pkg="${pkg#package:}"
        local allowed=0
        for a in "${ALLOWED_PKGS[@]}"; do
            [[ "$pkg" == "$a"* ]] && { allowed=1; break; }
        done
        if [[ $allowed -eq 0 ]]; then
            su -c "am force-stop '$pkg' 2>/dev/null" 2>/dev/null
            sleep 0.3
        fi
    done < <(su -c "pm list packages -3" 2>/dev/null)
    set "kill_unwanted_time" "$now"
}

# ============================================================
# CHECK CRASH — DOWNTIME TRACKING + SS SEKALI
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

    # Kirim notif PERTAMA dengan screenshot
    if [[ -z "$ss_sent" ]]; then
        discord "💀 Crash Detected" "**$name** has crashed!\nPackage: \`$pkg\`\nDowntime: **$downtime_str**" 16711680 "$(ss)"
        set "crash_ss_$pkg" "1"
        set "crash_update_$pkg" "$now"
        return 0
    fi

    # Update downtime tiap UPDATE_INTERVAL
    if [[ -n "$last_update" && $((now - last_update)) -lt $UPDATE_INTERVAL ]]; then
        return 0
    fi

    discord "💀 Still Down" "**$name** is still crashed.\nPackage: \`$pkg\`\nDowntime: **$downtime_str**" 16711680
    set "crash_update_$pkg" "$now"
}

# ============================================================
# HEAVY TASKS — GENTLE + BACKGROUND + LOCK
# ============================================================
heavy_tasks() {
    # Cek lock
    if [[ -f "$HEAVY_LOCK" ]]; then
        local lock_pid=$(cat "$HEAVY_LOCK" 2>/dev/null)
        kill -0 "$lock_pid" 2>/dev/null && return 0
        rm -f "$HEAVY_LOCK"
    fi

    # Jalanin di background dengan LOW priority
    (
        echo $$ > "$HEAVY_LOCK"
        local now=$(date +%s)

        # 1. Kill unwanted
        kill_unwanted

        # 2. Per package: cache + protect
        for pkg in "${PACKAGES[@]}"; do
            # Cache
            local last_c=$(get "c_$pkg")
            if [[ -z "$last_c" || $((now - last_c)) -ge $CACHE_INTERVAL ]]; then
                clear_cache "$pkg"
                set "c_$pkg" "$now"
            fi

            # Protect
            protect_app "$pkg"

            sleep 0.5
        done

        rm -f "$HEAVY_LOCK"
    ) &
}

# ============================================================
# CLEANUP
# ============================================================
cleanup() {
    init_packages
    for pkg in "${PACKAGES[@]}"; do su -c "am force-stop $pkg 2>/dev/null"; done
    rm -f "$PID_FILE"
    rm -f "$HEAVY_LOCK"
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

    # Startup notification
    local startup_msg="🚀 **Daemon Started**\n"
    startup_msg+="📦 Packages: ${#PACKAGES[@]}\n"
    for pkg in "${PACKAGES[@]}"; do
        startup_msg+="• \`$pkg\`\n"
    done
    startup_msg+="\n⏱️ **Intervals:**\n"
    startup_msg+="• ⚡ Crash check: ${CHECK_INTERVAL}s\n"
    startup_msg+="• 🔧 Heavy tasks: ${HEAVY_INTERVAL}s\n"
    startup_msg+="• 📊 Downtime update: ${UPDATE_INTERVAL}s\n\n"
    startup_msg+="⚠️ **Auto-restart: DISABLED**\n"
    startup_msg+="Crash = notif + screenshot (1x) + downtime tracking."
    discord "🚀 RobloxBot Started" "$startup_msg" 3066993

    # Fresh start
    for pkg in "${PACKAGES[@]}"; do
        su -c "am force-stop $pkg 2>/dev/null"
    done
    sleep 2

    # Launch sekali
    local i=0
    for pkg in "${PACKAGES[@]}"; do
        launch "$pkg" "${pkg##*.}"
        (( i++ )); (( i < ${#PACKAGES[@]} )) && sleep 30
    done

    # LOOP UTAMA
    local heavy_counter=0
    local heavy_threshold=$(( HEAVY_INTERVAL / CHECK_INTERVAL ))

    while true; do
        # 1. Cek crash — tiap 2 detik
        for pkg in "${PACKAGES[@]}"; do
            check_crash "$pkg" "${pkg##*.}"
        done

        # 2. Heavy tasks — tiap 60 detik
        ((heavy_counter++))
        if [[ $heavy_counter -ge $heavy_threshold ]]; then
            heavy_counter=0
            heavy_tasks
        fi

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
    nohup bash "$0" daemon >/dev/null 2>&1 &
    sleep 1
    if [[ -f "$PID_FILE" ]]; then
        discord "✅ Started" "Bot daemon started.\nPID: $(cat $PID_FILE)\n\n⚡ Crash check: ${CHECK_INTERVAL}s\n🔧 Heavy tasks: ${HEAVY_INTERVAL}s\n📊 Downtime update: ${UPDATE_INTERVAL}s\n\n⚠️ Auto-restart: DISABLED" 3066993
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
    status_msg+="• 🔧 Heavy tasks: ${HEAVY_INTERVAL}s\n"
    status_msg+="• 📊 Downtime update: ${UPDATE_INTERVAL}s\n\n"

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
    discord "🧪 Test" "Webhook working! (Simple + Gentle version)" 3447003
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
    rm -f "$HEAVY_LOCK"
    rm -f "${TMP_DIR}"/rb_*.png 2>/dev/null
    discord "🔄 Reset" "State DB and temp files reset successfully." 3447003
    exit 0
fi

# ============================================================
# HELP
# ============================================================
help_msg="🎮 **RobloxBot | SIMPLE + GENTLE**

"
help_msg+="**Usage:**\n"
help_msg+="\`start\` — Start daemon\n"
help_msg+="\`stop\` — Stop daemon & kill Roblox\n"
help_msg+="\`restart\` — Restart daemon\n"
help_msg+="\`status\` — Check status (sends to Discord)\n"
help_msg+="\`test-webhook\` — Test Discord webhook\n"
help_msg+="\`test-screenshot\` — Test screenshot\n"
help_msg+="\`reset-state\` — Reset state DB\n\n"
help_msg+="**⏱️ Intervals (cuma 3):**\n"
help_msg+="• Crash check: ${CHECK_INTERVAL}s\n"
help_msg+="• Heavy tasks: ${HEAVY_INTERVAL}s\n"
help_msg+="• Downtime update: ${UPDATE_INTERVAL}s\n\n"
help_msg+="**🔒 Features:**\n"
help_msg+="• Auto-restart: **DISABLED**\n"
help_msg+="• Screenshot: **1x per crash**\n"
help_msg+="• Downtime: tracked & updated\n"
help_msg+="• Heavy tasks: gentle (low priority + delays)\n"
help_msg+="• All output: Discord only"

discord "❓ Help" "$help_msg" 3447003