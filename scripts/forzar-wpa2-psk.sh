#!/usr/bin/env bash
# Fuerza WPA2-PSK y desactiva PMF en un perfil de NetworkManager.
# Pensado para el AIC8800D80 cuando el AP anuncia WPA2/WPA3 y SAE falla.
#
# Uso:
#   ./forzar-wpa2-psk.sh [SSID]
#
# El perfil debe existir previamente con su contraseña guardada.
# Este script no lee, no pide y no imprime la PSK.
#
# ADVERTENCIA: nmcli connection up reinicia la conexión WiFi. No lo ejecutes
# por SSH sin acceso alternativo (Ethernet, consola local u otra red).
set -euo pipefail

SSID="${1:-Conejos_5G}"

if ! command -v nmcli >/dev/null 2>&1; then
    echo "ERROR: nmcli no está disponible (¿NetworkManager instalado?)" >&2
    exit 1
fi

if ! nmcli -t -f NAME connection show | grep -Fxq "$SSID"; then
    echo "ERROR: no existe el perfil '$SSID'." >&2
    echo "Créalo primero conectándote al SSID:" >&2
    echo "  nmcli device wifi connect '$SSID' password 'TU_CONTRASEÑA'" >&2
    exit 1
fi

echo "==> Perfil antes de los cambios:"
nmcli -f 802-11-wireless-security.key-mgmt,802-11-wireless-security.pmf \
    connection show "$SSID"

echo "==> Forzando WPA2-PSK y PMF desactivado"
nmcli connection modify "$SSID" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.pmf 1

echo "==> Reactivando '$SSID' (se reinicia la conexión WiFi)"
if ! nmcli connection up "$SSID"; then
    echo "ERROR: no se pudo reactivar. Prueba con: sudo nmcli connection up '$SSID'" >&2
    exit 1
fi

DEV="$(nmcli -g GENERAL.DEVICES connection show "$SSID" 2>/dev/null | awk -F'[;|]' '{print $1}')"
if [[ -z "$DEV" || "$DEV" == "--" ]]; then
    DEV="wlan0"
fi

echo
echo "==> Perfil después de los cambios:"
nmcli -f 802-11-wireless-security.key-mgmt,802-11-wireless-security.pmf \
    connection show "$SSID"

echo
echo "==> Estado del dispositivo $DEV:"
nmcli -f GENERAL.STATE,GENERAL.CONNECTION dev show "$DEV" 2>/dev/null || true
if command -v iw >/dev/null 2>&1; then
    iw dev "$DEV" link 2>/dev/null || true
fi
