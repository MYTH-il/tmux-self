#!/usr/bin/env bash
# shellcheck shell=bash

# Prints the WAN IP address for 4 seconds without connecting to the internet.
# If connected via SSH, nothing is shown.
# While active, background turns red.

# Customize symbol and color
TMUX_POWERLINE_SEG_WAN_IP_SYMBOL="${TMUX_POWERLINE_SEG_WAN_IP_SYMBOL:-ⓦ }"
TMUX_POWERLINE_SEG_WAN_IP_SYMBOL_COLOUR="${TMUX_POWERLINE_SEG_WAN_IP_SYMBOL_COLOUR:-255}"
#TMUX_POWERLINE_SEG_WAN_IP_BG_COLOUR_RED="${TMUX_POWERLINE_SEG_WAN_IP_BG_COLOUR_RED:-1}"
WAN_IP_DISPLAY_TIME=4

generate_segmentrc() {
    read -r -d '' rccontents <<EORC
# Symbol for WAN IP
# export TMUX_POWERLINE_SEG_WAN_IP_SYMBOL="${TMUX_POWERLINE_SEG_WAN_IP_SYMBOL}"
# Symbol colour for WAN IP
# export TMUX_POWERLINE_SEG_WAN_IP_SYMBOL_COLOUR="${TMUX_POWERLINE_SEG_WAN_IP_SYMBOL_COLOUR}"
# Background colour when showing WAN IP
# export TMUX_POWERLINE_SEG_WAN_IP_BG_COLOUR_RED="${TMUX_POWERLINE_SEG_WAN_IP_BG_COLOUR_RED}"
# WAN IP display duration
# export WAN_IP_DISPLAY_TIME=$WAN_IP_DISPLAY_TIME
EORC
    echo "$rccontents"
}

run_segment() {
    # Only show WAN IP when environment variable is set
    if [ "$(tmux show-environment -g SHOW_WAN_IP 2>/dev/null | cut -d= -f2)" != "1" ]; then
        return 0
    fi

    local tmp_file="${TMUX_POWERLINE_DIR_TEMPORARY}/wan_ip.txt"
    local wan_ip

    # Create temporary directory if it doesn't exist
    mkdir -p "$(dirname "$tmp_file")"

    # Try to get WAN IP fresh from internet
    if command -v curl >/dev/null 2>&1; then
        wan_ip=$(curl --max-time 2 -s https://whatismyip.akamai.com/)
    fi

    # If curl failed, fall back to cached value
    if [ -z "$wan_ip" ] && [ -f "$tmp_file" ]; then
        wan_ip=$(cat "$tmp_file")
    fi

    # If got a new WAN IP, update the cache
    if [ -n "$wan_ip" ]; then
        echo "$wan_ip" > "$tmp_file"
        # Highlight the WAN IP with red background while showing
        echo "#[fg=$TMUX_POWERLINE_SEG_WAN_IP_SYMBOL_COLOUR]${TMUX_POWERLINE_SEG_WAN_IP_SYMBOL}#[fg=$TMUX_POWERLINE_CUR_SEGMENT_FG]${wan_ip}"
    fi

    return 0
}


