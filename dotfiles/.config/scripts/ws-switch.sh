#!/bin/sh
# Switch workspace via wtype (simulate Super+N) + update indicator
echo "$1" > /tmp/workspace
wtype -M logo -P "$1" -p "$1" -m logo 2>/dev/null
