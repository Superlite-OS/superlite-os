#!/bin/sh
TCP=$(ss -t state established 2>/dev/null | tail -n +2 | wc -l)
UDP=$(ss -u state established 2>/dev/null | tail -n +2 | wc -l)
printf "TCP %s  UDP %s" "$TCP" "$UDP"
