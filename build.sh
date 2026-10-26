#!/usr/bin/env bash
# Recompila el driver AIC8800 (WiFi + Bluetooth) para el kernel en ejecución.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WIFI_DIR="$SCRIPT_DIR/src/USB/driver_fw/drivers/aic8800"
BT_DIR="$SCRIPT_DIR/src/USB/driver_fw/drivers/aic_btusb"
KVER="$(uname -r)"

if ! command -v clang >/dev/null 2>&1; then
    echo "ERROR: falta clang (el kernel de CachyOS se compila con clang/LLVM)."
    echo "Instala: sudo pacman -S --needed clang lld llvm"
    exit 1
fi

if [[ ! -e "/lib/modules/$KVER/build" ]]; then
    echo "ERROR: faltan los headers de $KVER."
    echo "Instala: sudo pacman -S linux-cachyos-headers"
    exit 1
fi

echo "==> Compilando WiFi (aic_load_fw + aic8800_fdrv) para $KVER"
make -C "$WIFI_DIR" clean >/dev/null 2>&1 || true
make -C "$WIFI_DIR" LLVM=1 -j"$(nproc)"

echo "==> Compilando Bluetooth (aic_btusb) para $KVER"
make -C "$BT_DIR" clean >/dev/null 2>&1 || true
make -C "$BT_DIR" LLVM=1 -j"$(nproc)"

echo
echo "Compilación terminada:"
ls -lh "$WIFI_DIR/aic_load_fw/aic_load_fw.ko" \
       "$WIFI_DIR/aic8800_fdrv/aic8800_fdrv.ko" \
       "$BT_DIR/aic_btusb.ko"
echo
echo "Instala ahora con: sudo $SCRIPT_DIR/install.sh"
