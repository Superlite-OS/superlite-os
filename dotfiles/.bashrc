# ~/.bashrc — sourced by interactive bash shells
# Common aliases and shell config are in .profile

# Source .profile for shared aliases and setup
[ -f "$HOME/.profile" ] && . "$HOME/.profile"

# Google Drive setup shortcut
alias gdrive-setup='~/.config/scripts/google-drive-setup.sh'

# Prompt
PS1='\[\e[1;37m\][\u@\W]\$\[\e[0m\] '
