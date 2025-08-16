#!/bin/bash
# toggle_wan_ip.sh

# Tell tmux to set an environment variable
tmux set-environment -g SHOW_WAN_IP 1

# Refresh the tmux statusline
tmux refresh-client -S

# Wait 4 seconds
sleep 4

# Turn off the WAN IP display
tmux set-environment -gu SHOW_WAN_IP

# Refresh again to hide it
tmux refresh-client -S

