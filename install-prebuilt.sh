#!/usr/bin/env bash
# Instala los módulos AIC8800 USB ya compilados (release precompilado).
#
# Uso:
#   sudo ./install-prebuilt.sh [directorio-de-los-.ko]
#
# Por defecto usa el directorio del script. Si existe ./firmware (incluido en
# el tarball del release), instala también el firmware.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KVER="${KVER:-$(uname -r)}"
MODDIR="/lib/modules/$KVER/updates/aic8800"
SRC_DIR="${1:-$SCRIPT_DIR}"
MODS=(aic_load_fw aic8800_fdrv aic_btusb)

if [[ ${EUID} -ne 0 ]]; then
    echo "Este script necesita root. Ejecútalo así:"
    echo "  sudo $0"
    exit 1
fi

for m in "${MODS[@]}"; do
    if [[ ! -f "$SRC_DIR/$m.ko" ]]; then
        echo "ERROR: falta $SRC_DIR/$m.ko"
        exit 1
    fi
    vm="$(modinfo -F vermagic "$SRC_DIR/$m.ko" | awk '{print $1}')"
    if [[ "$vm" != "$KVER" ]]; then
        echo "ERROR: $m.ko fue compilado para '$vm' y el kernel actual es '$KVER'."
        echo "Descarga el release correspondiente a tu kernel o recompila:"
        echo "  ./build.sh && sudo ./install.sh"
        exit 1
    fi
done

if command -v dkms >/dev/null 2>&1 && dkms status 2>/dev/null | grep -q '^aic8800-usb'; then
    echo "Aviso: hay una instalación DKMS de aic8800-usb. Si los módulos no"
    echo "se actualizan, elimínala con:"
    echo "  sudo dkms remove aic8800-usb/1.0.0 --all"
fi

if [[ -d "$SCRIPT_DIR/firmware" ]]; then
    echo "==> Instalando firmware en /lib/firmware/aic8800_fw/USB"
    install -d -m 755 /lib/firmware/aic8800_fw/USB
    cp -a "$SCRIPT_DIR/firmware/." /lib/firmware/aic8800_fw/USB/
else
    echo "==> No hay firmware/ junto al script; se conserva el ya instalado"
fi

echo "==> Instalando módulos en $MODDIR"
install -d -m 755 "$MODDIR"
files=()
for m in "${MODS[@]}"; do
    files+=("$SRC_DIR/$m.ko")
done
install -m 644 "${files[@]}" "$MODDIR/"
depmod -a "$KVER"

echo "==> Configurando carga automática de módulos"
install -d -m 755 /etc/modules-load.d /etc/modprobe.d

cat > /etc/modules-load.d/aic8800.conf <<'EOF'
# AIC8800 USB (WiFi + Bluetooth)
aic_load_fw
aic8800_fdrv
aic_btusb
EOF

cat > /etc/modprobe.d/aic8800.conf <<'EOF'
# El combo AIC8800 usa su propio transporte HCI. Registrarlo antes que
# btusb para que se quede con la interfaz Bluetooth del adaptador.
softdep btusb pre: aic_btusb
EOF

echo "==> Cargando módulos"
set +e
for m in aic_btusb aic8800_fdrv aic_load_fw; do
    modprobe -r "$m" 2>/dev/null
done
modprobe -r btusb 2>/dev/null
set -e

modprobe aic_load_fw
sleep 2
modprobe aic8800_fdrv
modprobe aic_btusb
systemctl enable --now bluetooth 2>/dev/null || true

for _ in $(seq 1 15); do
    compgen -G "/sys/class/net/wlan*" >/dev/null 2>&1 || \
    compgen -G "/sys/class/net/wlp*" >/dev/null 2>&1 || { sleep 1; continue; }
    break
done

echo
echo "================ Estado ================"
echo "--- Interfaces de red ---"
ip -br link || true
echo "--- rfkill ---"
rfkill list || true
echo "--- Bluetooth ---"
timeout 5 bluetoothctl list 2>/dev/null || true
echo "--- Módulos cargados ---"
lsmod | grep -E '^(aic|btusb)' || true
echo "--- Últimas líneas del kernel ---"
dmesg | grep -iE 'aic|8800|wlan|hci|bluetooth|firmware' | tail -n 40 || true
echo "========================================"
