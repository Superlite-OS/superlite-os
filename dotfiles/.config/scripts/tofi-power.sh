#!/bin/sh
case $(printf "%s\n" "Logout" "Reboot" "Suspend" "Shutdown" | tofi -c "$HOME/.config/tofi/config_power_bottom" "$@") in
	"Logout")
		labwc --exit
		;;
	"Reboot")
		sudo reboot -i
		;;
	"Suspend")
		sudo zzz
		;;
	"Shutdown")
		sudo poweroff -i
		;;
esac
