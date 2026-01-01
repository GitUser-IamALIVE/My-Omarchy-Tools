Terminal or GUI tools I made For Omarchy.
1. Caffine Terminal ; a caffine i.e idle inhibitor TUI for Omarchy.
   example usecase : keybind for hyprland
bind = SUPER SHIFT, J, exec, bash -c 'FILE="$HOME/.config/Omarchy-Tools-TUI/termcaffine.sh"; [ -f "$FILE" ] || { mkdir -p "$(dirname "$FILE")" && curl -L -o "$FILE" "https://raw.githubusercontent.com/GitUser-IamALIVE/My-Omarchy-Tools/f839f20c0af4a4a074e944fb7c206830fbed3517/termcaffine.sh" && chmod +x "$FILE"; }; uwsm-app -- alacritty --class caffine-terminal-float-custom -e bash "$FILE"'

