#!/usr/bin/env bash

if [[ $1 = "toggle" ]]; then
	if pgrep -x "gammastep" > /dev/null; then
		pid=$(pgrep -x "gammastep")
		if [ -n "$pid" ]; then
			kill -15 "$pid"
		fi
	else
		gammastep -O 5600  2>/dev/null &
	fi
fi

if pgrep -x "gammastep" > /dev/null; then
	echo '{"text":"ON","class":"active","tooltip":"Night Light ON (5600K)"}'
else
	echo '{"text":"OFF","class":"inactive","tooltip":"Night Light OFF"}'
fi
