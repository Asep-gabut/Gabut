#!/data/data/com.termux/files/usr/bin/bash

INSTANCES=(
   "free.nokaA|https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server|Bot1"
   "free.nokaB|https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server|Bot2"
)

CHECK_INTERVAL="10"
CACHE_INTERVAL="3600"
FREEZE_THRESHOLD="60"
MAX_RESTARTS="50"

DISCORD_WEBHOOK="https://discord.com/api/webhooks/1483451715104804964/o0vgYLS-zg4WUXHQM-GiaT0idCfzz-bqPAqRXi4ME0xjEQusxdA3zmEdRQIzUiHovOb3"
DISCORD_PING_USER=""

PID_FILE="/data/data/com.termux/files/usr/tmp/roblox_bot.pid"
STATE_FILE="/data/data/com.termux/files/usr/tmp/roblox_state"
SCRIPT_PATH="$(realpath "$0")"

declare -A INSTANCE_STATE

discord_send() {
    local title="$1"
    local description="$2"
    local color="$3"
    local image_path="$4"
    [[ -z "$DISCORD_WEBHOOK" ]] && return
    local ping=""
    [[ -n "$DISCORD_PING_USER" ]] && ping="<@$DISCORD_PING_USER> "
    if [[ -n "$image_path" && -f "$image_path" ]]; then
        local boundary="----BotBoundary$(date +%s)"
        {
            echo "--$boundary"
            echo 'Content-Disposition: form-data; name="payload_json"'
            echo 'Content-Type: application/json'
            echo ""
            echo "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$description\",\"color\":$color,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"footer\":{\"text\":\"Roblox Bot • Termux\"}}]}"
            echo "--$boundary"
            echo 'Content-Disposition: form-data; name="file"; filename="screenshot.png"'
            echo 'Content-Type: image/png'
            echo ""
            cat "$image_path"
            echo ""
            echo "--$boundary--"
        } | curl -s -X POST -H "Content-Type: multipart/form-data; boundary=$boundary" --data-binary @- "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
    else
        local json="{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$description\",\"color\":$color,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"footer\":{\"text\":\"Roblox Bot • Termux\"}}]}"
        curl -s -H "Content-Type: application/json" -X POST -d "$json" "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
    fi
}

take_screenshot() {
    local path="/sdcard/roblox_crash_$(date +%s).png"
    su -c "screencap -p $path" 2>/dev/null
    [[ -f "$path" ]] && echo "$path" || echo ""
}

if ! su -c "id" >/dev/null 2>&1; then
    echo "❌ Root access denied!"
    exit 1
fi

load_state() {
    [[ -f "$STATE_FILE" ]] && source "$STATE_FILE" 2>/dev/null
}

save_state() {
    {
        echo "# Roblox Bot State — $(date)"
        for key in "${!INSTANCE_STATE[@]}"; do
            echo "INSTANCE_STATE[$key]=\"${INSTANCE_STATE[$key]}\""
        done
    } > "$STATE_FILE"
}

is_running() {
    local pkg="$1"
    local pid
    pid=$(su -c "pidof $pkg" 2>/dev/null)
    [[ -z "$pid" ]] && return 1
    local state
    state=$(su -c "cat /proc/$pid/stat 2>/dev/null | awk '{print \$3}'")
    [[ "$state" == "Z" ]] && return 1
    su -c "dumpsys window windows | grep -q '$pkg'" 2>/dev/null
}

is_frozen() {
    local pkg="$1"
    local pid
    pid=$(su -c "pidof $pkg" 2>/dev/null)
    [[ -z "$pid" ]] && return 1
    local stat_file="/proc/$pid/stat"
    [[ ! -f "$stat_file" ]] && return 1
    local cpu_time
    cpu_time=$(su -c "cat $stat_file" 2>/dev/null | awk '{print $14+$15}')
    [[ -z "$cpu_time" ]] && return 1
    local cache_key="cpu_${pkg}"
    local last_cpu="${INSTANCE_STATE[$cache_key]:-0}"
    if [[ "$last_cpu" == "$cpu_time" ]]; then
        local frozen_since="${INSTANCE_STATE[${cache_key}_time]:-$(( $(date +%s) - FREEZE_THRESHOLD - 1 ))}"
        local now=$(date +%s)
        if (( now - frozen_since >= FREEZE_THRESHOLD )); then
            return 0
        fi
    else
        INSTANCE_STATE["$cache_key"]="$cpu_time"
        INSTANCE_STATE["${cache_key}_time"]="$(date +%s)"
    fi
    return 1
}

launch() {
    local pkg="$1"
    local url="$2"
    local name="$3"
    if is_running "$pkg"; then
        return 0
    fi
    su -c "am start -a android.intent.action.VIEW -d '$url' -p $pkg" >/dev/null 2>&1
    sleep 15
    is_running "$pkg"
}

kill_pkg() {
    su -c "am force-stop $1" >/dev/null 2>&1
}

clear_cache() {
    local pkg="$1"
    local pkg_dir="/data/data/$pkg"
    local cache_dirs
    cache_dirs=$(su -c "find $pkg_dir -maxdepth 1 -type d -iname '*cache*' 2>/dev/null")
    if [[ -n "$cache_dirs" ]]; then
        while IFS= read -r dir; do
            [[ -n "$dir" ]] && su -c "rm -rf $dir/*" 2>/dev/null
        done <<< "$cache_dirs"
    fi
    local ext_cache="/sdcard/Android/data/$pkg/cache"
    [[ -d "$ext_cache" ]] && su -c "rm -rf $ext_cache/*" 2>/dev/null
}

process_instance() {
    local idx="$1"
    local line="$2"
    IFS='|' read -r pkg url name <<< "$line"
    local state="${INSTANCE_STATE[$idx]:-0|0|0|0}"
    local last_cache restarts last_restart uptime
    IFS='|' read -r last_cache restarts last_restart uptime <<< "$state"
    local now_epoch=$(date +%s)
    local today=$(date +%Y%m%d)
    local today_key="day_${idx}_${today}"
    local today_restarts="${INSTANCE_STATE[$today_key]:-0}"
    local grace_key="grace_${idx}"
    local grace_until="${INSTANCE_STATE[$grace_key]:-0}"

    if (( now_epoch < grace_until )); then
        return
    fi

    if ! is_running "$pkg"; then
        if (( today_restarts >= MAX_RESTARTS )); then
            discord_send "⚠️ Max Restarts" "**$name** skip (udah $today_restarts kali)." 15158332
            return
        fi
        discord_send "💀 Crash" "**$name** crash. Restarting..." 16711680 "$(take_screenshot)"
        launch "$pkg" "$url" "$name"
        INSTANCE_STATE["$grace_key"]="$((now_epoch + 30))"
        ((restarts++)); ((today_restarts++))
        INSTANCE_STATE["$idx"]="$now_epoch|$restarts|$now_epoch|$uptime"
        INSTANCE_STATE["$today_key"]="$today_restarts"
        save_state
        discord_send "🚀 Restarted" "**$name** restart. Total: $restarts" 3066993
        return
    fi

    if is_frozen "$pkg"; then
        if (( today_restarts >= MAX_RESTARTS )); then
            return
        fi
        discord_send "🥶 Frozen" "**$name** freeze. Restarting..." 16711680 "$(take_screenshot)"
        kill_pkg "$pkg"
        sleep 2
        clear_cache "$pkg"
        sleep 1
        launch "$pkg" "$url" "$name"
        INSTANCE_STATE["$grace_key"]="$((now_epoch + 30))"
        ((restarts++)); ((today_restarts++))
        INSTANCE_STATE["$idx"]="$now_epoch|$restarts|$now_epoch|$uptime"
        INSTANCE_STATE["$today_key"]="$today_restarts"
        save_state
        discord_send "🚀 Restarted" "**$name** restart setelah freeze." 3066993
        return
    fi

    if [[ "$CACHE_INTERVAL" != "0" ]] && (( now_epoch - last_cache >= CACHE_INTERVAL )); then
        discord_send "🧹 Cache Clear" "**$name** cache clear." 3447003
        kill_pkg "$pkg"
        sleep 2
        clear_cache "$pkg"
        sleep 1
        launch "$pkg" "$url" "$name"
        INSTANCE_STATE["$grace_key"]="$((now_epoch + 30))"
        INSTANCE_STATE["$idx"]="$now_epoch|$restarts|$last_restart|$uptime"
        save_state
        discord_send "🚀 Relaunched" "**$name** restart setelah cache clear." 3066993
        return
    fi

    if (( last_restart > 0 )); then
        INSTANCE_STATE["$idx"]="$last_cache|$restarts|$last_restart|$((uptime + CHECK_INTERVAL))"
    fi
}

cleanup_all() {
    for line in "${INSTANCES[@]}"; do
        IFS='|' read -r pkg _ _ <<< "$line"
        kill_pkg "$pkg"
    done
    rm -f "$PID_FILE" "$STATE_FILE"
}

if [[ "$1" == "--daemon" ]]; then
    echo $$ > "$PID_FILE"
    load_state
    trap 'cleanup_all; discord_send "🛑 Stopped" "Bot dimatikan." 15158332; exit 0' SIGTERM SIGINT
    discord_send "🚀 Started" "Bot aktif: **${#INSTANCES[@]}** instance." 3066993

    local i=0
    for line in "${INSTANCES[@]}"; do
        IFS='|' read -r pkg url name <<< "$line"
        launch "$pkg" "$url" "$name"
        ((i++))
        (( i < ${#INSTANCES[@]} )) && sleep 5
    done

    while true; do
        i=0
        for line in "${INSTANCES[@]}"; do
            process_instance "$i" "$line"
            ((i++))
        done
        save_state
        sleep "$CHECK_INTERVAL"
    done
    exit 0
fi

case "$1" in
    start)
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && echo "❌ Already running" && exit 1
        nohup bash "$SCRIPT_PATH" --daemon > /dev/null 2>&1 &
        sleep 1
        [[ -f "$PID_FILE" ]] && echo "✅ Started" || echo "❌ Failed"
        ;;
    stop)
        [[ -f "$PID_FILE" ]] && kill "$(cat "$PID_FILE")" 2>/dev/null && sleep 1 && kill -9 "$(cat "$PID_FILE")" 2>/dev/null
        rm -f "$PID_FILE"
        for line in "${INSTANCES[@]}"; do IFS='|' read -r pkg _ _ <<< "$line"; kill_pkg "$pkg"; done
        rm -f "$STATE_FILE"
        discord_send "🛑 Stopped" "Bot dimatikan manual." 15158332
        echo "🛑 Stopped"
        ;;
    restart) bash "$SCRIPT_PATH" stop; sleep 2; bash "$SCRIPT_PATH" start ;;
    status)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "🟢 Running"
            load_state
            local i=0
            for line in "${INSTANCES[@]}"; do
                IFS='|' read -r pkg _ name <<< "$line"
                local state="${INSTANCE_STATE[$i]:-0|0|0|0}"
                local _c restarts _r uptime
                IFS='|' read -r _c restarts _r uptime <<< "$state"
                is_running "$pkg" && echo "   🟢 $name | Restarts: $restarts" || echo "   🔴 $name | Restarts: $restarts"
                ((i++))
            done
        else
            echo "🔴 Stopped"
        fi
        ;;
    test-webhook)
        [[ -z "$DISCORD_WEBHOOK" ]] && echo "❌ Webhook not set" && exit 1
        discord_send "🧪 Test" "Webhook OK." 3447003
        echo "✅ Sent"
        ;;
    test-screenshot)
        local ss; ss=$(take_screenshot)
        [[ -n "$ss" ]] && echo "✅ $ss" && discord_send "🧪 Screenshot" "Test." 3447003 "$ss" || echo "❌ Failed"
        ;;
    test-launch)
        IFS='|' read -r pkg url name <<< "${INSTANCES[0]}"
        launch "$pkg" "$url" "$name" && echo "✅ Launched" || echo "❌ Failed"
        ;;
    reset-state) rm -f "$STATE_FILE"; echo "✅ Reset" ;;
    *) echo "🎮 Roblox Bot | start|stop|restart|status|test-webhook|test-screenshot|test-launch|reset-state" ;;
esac