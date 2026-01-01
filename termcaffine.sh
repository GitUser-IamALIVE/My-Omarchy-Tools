#!/usr/bin/env bash

# Terminal Caffeine - NerdHUD v3.3
# A terminal-based system sleep inhibitor for Linux/Wayland

set -euo pipefail

# === GLOBALS ===
SESSION_ID=""
START_TIME=0
CAFFEINE_ACTIVE=1
TIMER_MODE="infinite"
TIMER_REMAINING=0
TIMER_PAUSED_AT=0
INHIBIT_PID=0
INITIAL_MINUTES=0
LAST_UPDATE=0

# Colors
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_CYAN='\033[96m'
C_GREEN='\033[92m'
C_YELLOW='\033[93m'
C_RED='\033[91m'
C_BLUE='\033[94m'
C_MAGENTA='\033[95m'

# Box drawing constants
BOX_WIDTH=64
CONTENT_WIDTH=62

# === UTILITY FUNCTIONS ===

generate_session_id() {
    printf "%04X" $((RANDOM % 65536))
}

get_uptime() {
    local elapsed=$(($(date +%s) - START_TIME))
    printf "%02d:%02d" $((elapsed/3600)) $(((elapsed%3600)/60))
}

format_time() {
    local seconds=$1
    printf "%02d:%02d" $((seconds/3600)) $(((seconds%3600)/60))
}

print_line() {
    local content="$1"
    local display_len=${#content}
    local padding=$((CONTENT_WIDTH - display_len))
    printf "║ %s%*s ║\n" "$content" "$padding" ""
}

print_colored_line() {
    local content="$1"
    local plain_content=$(echo -e "$content" | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
    local display_len=${#plain_content}
    local padding=$((CONTENT_WIDTH - display_len))
    printf "║ %b%*s ║\n" "$content" "$padding" ""
}

draw_border() {
    local char="$1"
    local left="$2"
    local right="$3"
    printf "%b" "$C_CYAN"
    printf "%s" "$left"
    for ((i=0; i<CONTENT_WIDTH+2; i++)); do printf "%s" "$char"; done
    printf "%s\n" "$right"
    printf "%b" "$C_RESET"
}

# === STARTUP SCREEN ===

show_startup_prompt() {
    clear
    printf "${C_BOLD}${C_YELLOW}    ☕ Terminal Caffeine${C_RESET}\n\n"
    
    local BOX_W=49
    
    print_startup_line() {
        local content="$1"
        local plain_content=$(echo -e "$content" | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
        local display_len=${#plain_content}
        local padding=$((BOX_W - display_len))
        printf "${C_CYAN}║${C_RESET} %b%*s ${C_CYAN}║${C_RESET}\n" "$content" "$padding" ""
    }
    
    printf "${C_CYAN}╔"
    for ((i=0; i<BOX_W+2; i++)); do printf "═"; done
    printf "╗${C_RESET}\n"
    
    print_startup_line "Select timer duration:"
    print_startup_line ""
    print_startup_line "      ${C_YELLOW})  (${C_RESET}        ${C_GREEN}1${C_RESET} → 15 minutes"
    print_startup_line "     ${C_YELLOW}(   ) )${C_RESET}      ${C_GREEN}2${C_RESET} → 30 minutes"
    print_startup_line "      ${C_YELLOW}) ( (${C_RESET}       ${C_GREEN}3${C_RESET} → 45 minutes"
    print_startup_line "    ${C_YELLOW}_______)_${C_RESET}     ${C_GREEN}4${C_RESET} → 60 minutes"
    print_startup_line " ${C_YELLOW}.-'---------|${C_RESET}    ${C_YELLOW}0${C_RESET} → Infinite"
    print_startup_line "${C_YELLOW}( C|/\\/\\/\\/\\/|${C_RESET}    ${C_BLUE}6${C_RESET} → Custom"
    print_startup_line " ${C_YELLOW}'-./\\/\\/\\/\\/|${C_RESET}"
    print_startup_line "   ${C_YELLOW}'_________'${C_RESET}     ${C_DIM}Stack 1-4 to add time${C_RESET}"
    print_startup_line "    ${C_YELLOW}'-------'${C_RESET}      ${C_BOLD}Press key:${C_RESET}"
    
    printf "${C_CYAN}╚"
    for ((i=0; i<BOX_W+2; i++)); do printf "═"; done
    printf "╝${C_RESET}\n"
    
    local choice
    read -n 1 -r choice
    echo ""
    
    case "$choice" in
        1) INITIAL_MINUTES=15 ;;
        2) INITIAL_MINUTES=30 ;;
        3) INITIAL_MINUTES=45 ;;
        4) INITIAL_MINUTES=60 ;;
        0) INITIAL_MINUTES=0 ;;
        6)
            echo ""
            printf "${C_BOLD}Enter custom duration (minutes): ${C_RESET}"
            read -r custom
            INITIAL_MINUTES="${custom:-0}"
            ;;
        *) INITIAL_MINUTES=0 ;;
    esac
}

# === INHIBITION CONTROL ===

start_inhibit() {
    if [[ $INHIBIT_PID -eq 0 ]]; then
        if ! command -v systemd-inhibit &>/dev/null; then
            echo "ERROR: systemd-inhibit not found. This tool requires systemd."
            exit 1
        fi
        
        systemd-inhibit --what=idle:sleep:shutdown \
                        --who="Terminal Caffeine" \
                        --why="User requested system stay awake" \
                        --mode=block \
                        sleep infinity &
        INHIBIT_PID=$!
        CAFFEINE_ACTIVE=1
    fi
}

stop_inhibit() {
    if [[ $INHIBIT_PID -ne 0 ]]; then
        kill $INHIBIT_PID 2>/dev/null || true
        wait $INHIBIT_PID 2>/dev/null || true
        INHIBIT_PID=0
        CAFFEINE_ACTIVE=0
    fi
}

# === TIMER FUNCTIONS ===

set_timer() {
    local minutes=$1
    if [[ $minutes -eq 0 ]]; then
        TIMER_MODE="infinite"
        TIMER_REMAINING=0
    else
        TIMER_MODE="running"
        TIMER_REMAINING=$((minutes * 60))
    fi
    LAST_UPDATE=$(date +%s)
}

add_timer() {
    local minutes=$1
    
    if [[ "$TIMER_MODE" == "infinite" ]]; then
        # Start fresh with the specified time
        set_timer "$minutes"
    else
        # Add to existing timer
        TIMER_REMAINING=$((TIMER_REMAINING + minutes * 60))
        if [[ "$TIMER_MODE" == "paused" ]]; then
            TIMER_MODE="running"
            start_inhibit
        fi
        LAST_UPDATE=$(date +%s)
    fi
}

pause_timer() {
    if [[ "$TIMER_MODE" == "running" ]]; then
        TIMER_MODE="paused"
        TIMER_PAUSED_AT=$(date +%s)
        stop_inhibit  # Stop inhibition when paused
    elif [[ "$TIMER_MODE" == "paused" ]]; then
        # Resume to the appropriate mode based on remaining time
        if [[ $TIMER_REMAINING -eq 0 ]]; then
            TIMER_MODE="infinite"
        else
            TIMER_MODE="running"
        fi
        LAST_UPDATE=$(date +%s)
        start_inhibit  # Resume inhibition when unpaused
    elif [[ "$TIMER_MODE" == "infinite" ]]; then
        # Can pause infinite mode too
        TIMER_MODE="paused"
        TIMER_PAUSED_AT=$(date +%s)
        stop_inhibit
    fi
}

reset_timer() {
    TIMER_MODE="infinite"
    TIMER_REMAINING=0
    LAST_UPDATE=$(date +%s)
}

update_timer() {
    local now=$(date +%s)
    
    if [[ "$TIMER_MODE" == "running" && $TIMER_REMAINING -gt 0 ]]; then
        local elapsed=$((now - LAST_UPDATE))
        
        if [[ $elapsed -gt 0 ]]; then
            TIMER_REMAINING=$((TIMER_REMAINING - elapsed))
            LAST_UPDATE=$now
            
            if [[ $TIMER_REMAINING -le 0 ]]; then
                TIMER_REMAINING=0
                timer_expired
            fi
        fi
    fi
}

timer_expired() {
    stop_inhibit
    printf '\a'
    
    if command -v notify-send &>/dev/null; then
        notify-send -u critical "Terminal Caffeine" "Timer expired - system will sleep normally"
    fi
    
    clear
    printf "${C_YELLOW}⏰ Timer expired!${C_RESET} Press any key to exit...\n"
    read -n 1 -r -s
    cleanup_and_exit
}

# === UI RENDERING ===

draw_ui() {
    printf '\033[2J\033[H'  # Clear screen and move cursor to top
    
    local state_text="${C_GREEN}● ACTIVE${C_RESET}"
    local idle_text="${C_GREEN}BLOCKED${C_RESET}"
    
    if [[ $CAFFEINE_ACTIVE -eq 0 ]]; then
        if [[ "$TIMER_MODE" == "paused" ]]; then
            state_text="${C_YELLOW}⏸ PAUSED${C_RESET}"
            idle_text="${C_YELLOW}UNBLOCKED${C_RESET}"
        else
            state_text="${C_RED}○ INACTIVE${C_RESET}"
            idle_text="${C_RED}UNBLOCKED${C_RESET}"
        fi
    fi
    
    local uptime_str=$(get_uptime)
    local start_time_str=$(date -d "@$START_TIME" +%H:%M 2>/dev/null || date -r "$START_TIME" +%H:%M)
    local ends_at_str="∞"
    if [[ "$TIMER_MODE" == "paused" ]]; then
        # Show when timer was paused
        ends_at_str=$(date -d "@$TIMER_PAUSED_AT" +%H:%M 2>/dev/null || date -r "$TIMER_PAUSED_AT" +%H:%M)
    elif [[ "$TIMER_MODE" != "infinite" ]]; then
        local ends_at=$(($(date +%s) + TIMER_REMAINING))
        ends_at_str=$(date -d "@$ends_at" +%H:%M 2>/dev/null || date -r "$ends_at" +%H:%M)
    fi
    local remaining_str="∞"
    if [[ "$TIMER_MODE" != "infinite" ]]; then
        remaining_str=$(format_time $TIMER_REMAINING)
    fi
    
    # Header
    draw_border "═" "╔" "╗"
    print_colored_line "${C_BOLD}${C_CYAN}TERMINAL CAFFEINE${C_RESET}                   ${C_DIM}Session #${C_MAGENTA}$SESSION_ID${C_RESET}"
    draw_border "─" "╟" "╢"
    print_colored_line "${C_BOLD}${C_BLUE}STATUS${C_RESET} ${C_DIM}→${C_RESET} $state_text ${C_DIM}|${C_RESET} ${C_DIM}Up:${C_RESET}${C_CYAN}$uptime_str${C_RESET} ${C_DIM}|${C_RESET} ${C_DIM}Idle:${C_RESET}$idle_text"
    draw_border "─" "╟" "╢"

    # Timer section
    local timer_status=""
    case "$TIMER_MODE" in
        infinite)
            timer_status="${C_YELLOW}∞ INFINITE${C_RESET}"
            ;;
        running)
            timer_status="${C_GREEN}▶ RUNNING${C_RESET}"
            ;;
        paused)
            timer_status="${C_YELLOW}⏹ STOPPED${C_RESET}"
            ;;
    esac
    
    local inhibit_status="${C_GREEN}SUCCESS${C_RESET}"
    if [[ $CAFFEINE_ACTIVE -eq 0 ]]; then
        if [[ "$TIMER_MODE" == "paused" ]]; then
            inhibit_status="${C_YELLOW}STOPPED${C_RESET}"
        else
            inhibit_status="${C_RED}FAILED${C_RESET}"
        fi
    fi
    
    print_line ""
    print_colored_line "     ${C_YELLOW})  (${C_RESET}                 ${C_BOLD}${C_BLUE}TIMER${C_RESET} ${C_DIM}→${C_RESET} $timer_status"
    print_colored_line "    ${C_YELLOW}(   ) )${C_RESET}"
    print_colored_line "     ${C_YELLOW}) ( (${C_RESET}                 ${C_BOLD}Started:${C_RESET}  ${C_CYAN}$start_time_str${C_RESET}"
    print_colored_line "   ${C_YELLOW}_______)_${C_RESET}               ${C_BOLD}Ends at:${C_RESET}  ${C_CYAN}$ends_at_str${C_RESET}"
    print_colored_line "${C_YELLOW}.-'---------|${C_RESET}              ${C_BOLD}Remain:${C_RESET}   ${C_YELLOW}$remaining_str${C_RESET}"
    print_colored_line "${C_YELLOW}( C|/\\/\\/\\/\\/|${C_RESET}             ${C_BOLD}Inhibit:${C_RESET} $inhibit_status"
    print_colored_line "${C_YELLOW}'-./\\/\\/\\/\\/|${C_RESET}"
    print_colored_line "  ${C_YELLOW}'_________'${C_RESET}"
    print_colored_line "   ${C_YELLOW}'-------'${C_RESET}"
    
    draw_border "─" "╟" "╢"
    
    # Dynamic pause/start button label
    local pause_label="Pause"
    [[ "$TIMER_MODE" == "paused" ]] && pause_label="Start"
    
    print_colored_line "${C_GREEN}Q${C_RESET} Quit ${C_GREEN}T${C_RESET} Custom ${C_GREEN}P${C_RESET} $pause_label ${C_GREEN}R${C_RESET} Reset ${C_GREEN}H${C_RESET} Help"
    print_colored_line "${C_DIM}1-4${C_RESET} Add time ${C_DIM}|${C_RESET} ${C_DIM}Shift+1-4${C_RESET} Reset to preset ${C_DIM}|${C_RESET} ${C_GREEN}0${C_RESET} Infinite"
    draw_border "═" "╚" "╝"
}

show_timer_menu() {
    printf '\033[2J\033[H'  # Clear screen and move cursor to top
    printf "${C_CYAN}"
    draw_border "═" "╔" "╗"
    printf "${C_RESET}"
    print_colored_line "${C_BOLD}${C_YELLOW}SET TIMER${C_RESET}"
    draw_border "─" "╟" "╢"
    print_line ""
    print_colored_line "      ${C_YELLOW})  (${C_RESET}        ${C_GREEN}1${C_RESET} → Add 15 minutes"
    print_colored_line "     ${C_YELLOW}(   ) )${C_RESET}      ${C_GREEN}2${C_RESET} → Add 30 minutes"
    print_colored_line "      ${C_YELLOW}) ( (${C_RESET}       ${C_GREEN}3${C_RESET} → Add 45 minutes"
    print_colored_line "    ${C_YELLOW}_______)_${C_RESET}     ${C_GREEN}4${C_RESET} → Add 60 minutes"
    print_colored_line " ${C_YELLOW}.-'---------|${C_RESET}    ${C_YELLOW}0${C_RESET} → Set infinite"
    print_colored_line "${C_YELLOW}( C|/\\/\\/\\/\\/|${C_RESET}"
    print_colored_line " ${C_YELLOW}'-./\\/\\/\\/\\/|${C_RESET}    ${C_BLUE}C${C_RESET} → Custom duration"
    print_colored_line "   ${C_YELLOW}'_________'${C_RESET}"
    print_colored_line "    ${C_YELLOW}'-------'${C_RESET}      ${C_DIM}Q to cancel${C_RESET}"
    print_line ""
    print_colored_line "${C_YELLOW}Reset to preset:${C_RESET}"
    print_colored_line "${C_GREEN}!${C_RESET} 15m  ${C_GREEN}@${C_RESET} 30m  ${C_GREEN}#${C_RESET} 45m  ${C_GREEN}\$${C_RESET} 60m  ${C_DIM}(Shift+1-4)${C_RESET}"
    printf "${C_CYAN}"
    draw_border "═" "╚" "╝"
    printf "${C_RESET}\n"
    printf "${C_BOLD}Press a key:${C_RESET} "
    
    local choice
    read -n 1 -r -s choice
    echo ""
    
    case "$choice" in
        1) add_timer 15 ;;
        2) add_timer 30 ;;
        3) add_timer 45 ;;
        4) add_timer 60 ;;
        0) reset_timer ;;
        c|C)
            printf "\n${C_BOLD}Enter custom duration (minutes): ${C_RESET}"
            read -r custom
            if [[ -n "$custom" && "$custom" =~ ^[0-9]+$ ]]; then
                set_timer "$custom"
            fi
            ;;
        '!') set_timer 15 ;;
        '@') set_timer 30 ;;
        '#') set_timer 45 ;;
        '$') set_timer 60 ;;
        q|Q) ;;  # Cancel - do nothing
        *) ;;    # Any other key - cancel
    esac
    
    draw_ui  # Redraw UI after timer menu
}

show_help() {
    printf '\033[2J\033[H'  # Clear screen and move cursor to top
    printf "${C_CYAN}"
    draw_border "═" "╔" "╗"
    printf "${C_RESET}"
    print_colored_line "${C_BOLD}${C_YELLOW}HELP${C_RESET}"
    draw_border "─" "╟" "╢"
    print_colored_line "${C_GREEN}Q${C_RESET}       Quit and exit"
    print_line ""
    print_colored_line "${C_YELLOW}Quick Timer Presets (Stackable):${C_RESET}"
    print_colored_line "${C_GREEN}1${C_RESET}       Add 15 minutes to timer"
    print_colored_line "${C_GREEN}2${C_RESET}       Add 30 minutes to timer"
    print_colored_line "${C_GREEN}3${C_RESET}       Add 45 minutes to timer"
    print_colored_line "${C_GREEN}4${C_RESET}       Add 60 minutes to timer"
    print_line ""
    print_colored_line "${C_YELLOW}Reset to Preset:${C_RESET}"
    print_colored_line "${C_GREEN}!${C_RESET}       Reset to 15 min (Shift+1)"
    print_colored_line "${C_GREEN}@${C_RESET}       Reset to 30 min (Shift+2)"
    print_colored_line "${C_GREEN}#${C_RESET}       Reset to 45 min (Shift+3)"
    print_colored_line "${C_GREEN}\$${C_RESET}       Reset to 60 min (Shift+4)"
    print_line ""
    print_colored_line "${C_DIM}Example: Press 1+1+2 = 1h total${C_RESET}"
    printf "${C_CYAN}"
    draw_border "═" "╚" "╝"
    printf "${C_RESET}\n"
    printf "${C_DIM}Press any key to return...${C_RESET}\n"
    read -n 1 -r -s
    draw_ui  # Redraw UI after help
}

# === INPUT HANDLING ===

handle_input() {
    local key=""
    if read -t 0.05 -n 1 -r -s key 2>/dev/null; then
        case "$key" in
            q|Q) cleanup_and_exit ;;
            t|T) show_timer_menu ;;
            p|P) 
                pause_timer
                draw_ui
                ;;
            r|R) 
                reset_timer
                draw_ui
                ;;
            h|H) show_help ;;
            1) 
                add_timer 15
                draw_ui
                ;;
            2) 
                add_timer 30
                draw_ui
                ;;
            3) 
                add_timer 45
                draw_ui
                ;;
            4) 
                add_timer 60
                draw_ui
                ;;
            0) 
                reset_timer
                draw_ui
                ;;
            '!')
                set_timer 15
                draw_ui
                ;;
            '@')
                set_timer 30
                draw_ui
                ;;
            '#')
                set_timer 45
                draw_ui
                ;;
            '$')
                set_timer 60
                draw_ui
                ;;
        esac
    fi
}

# === STATUS COMMAND ===

print_status() {
    if [[ $CAFFEINE_ACTIVE -eq 1 ]]; then
        echo "ACTIVE"
        echo "uptime=$(get_uptime)"
        if [[ "$TIMER_MODE" == "infinite" ]]; then
            echo "timer=infinite"
        else
            echo "timer=$(format_time $TIMER_REMAINING)"
        fi
    else
        echo "INACTIVE"
    fi
}

# === CLEANUP ===

cleanup_and_exit() {
    stop_inhibit
    tput cnorm 2>/dev/null || true  # Restore cursor
    printf '\033[2J\033[H'  # Clear screen
    exit 0
}

# === MAIN LOOP ===

main_loop() {
    tput civis 2>/dev/null || true  # Hide cursor
    
    local last_draw=$(date +%s)
    LAST_UPDATE=$(date +%s)
    draw_ui
    
    while true; do
        handle_input
        update_timer
        
        local now=$(date +%s)
        # Redraw every 60 seconds for uptime updates
        if [[ $((now - last_draw)) -ge 60 ]]; then
            draw_ui
            last_draw=$now
        fi
        
        sleep 0.2
    done
}

# === ENTRY POINT ===

main() {
    if [[ "${1:-}" == "--status" ]]; then
        print_status
        exit 0
    fi
    
    trap cleanup_and_exit EXIT INT TERM
    SESSION_ID=$(generate_session_id)
    START_TIME=$(date +%s)
    
    show_startup_prompt
    set_timer "$INITIAL_MINUTES"
    start_inhibit
    main_loop
}

main "$@"