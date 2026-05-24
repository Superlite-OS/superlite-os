#!/bin/sh
# SuperLite OS — VPN Connect/Disconnect with notification

case "$1" in
    connect)
        OUTPUT=$(wg-quick up wg0 2>&1)
        if [ $? -eq 0 ]; then
            notify-send -i network-vpn "VPN Connected" "WireGuard VPN aktif"
        else
            notify-send -i dialog-error "VPN Gagal" "Gagal menghubungkan VPN: $OUTPUT"
        fi
        ;;
    disconnect)
        OUTPUT=$(wg-quick down wg0 2>&1)
        if [ $? -eq 0 ]; then
            notify-send -i network-vpn-disconnected "VPN Disconnected" "WireGuard VPN dimatikan"
        else
            notify-send -i dialog-error "VPN Gagal" "Gagal memutuskan VPN: $OUTPUT"
        fi
        ;;
esac
