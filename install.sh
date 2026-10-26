#!/usr/bin/env bash
# Instalador del driver AIC8800 (WiFi + Bluetooth) para CachyOS / Linux 7.3
#
# Uso:
#   sudo ./install.sh            # instala los módulos ya compilados (kernel actual)
#   sudo ./install.sh --dkms     # instala vía DKMS (sobrevive a updates de kernel)
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KVER="${KVER:-$(uname -r)}"
MODE="manual"

usage() {
    cat <<EOF
Uso: sudo $0 [--dkms|--manual]

  --dkms    Registrar el driver en DKMS y compilarlo para el kernel $KVER.
            Recomendado: se recompila solo en cada actualización de kernel.
  --manual  Instalar los .ko ya compilados para el kernel actual (por defecto).

Variables:
  KVER=...  Kernel destino (por defecto: $(uname -r))
EOF
}

case "${1:-}" in
    --dkms)   MODE="dkms" ;;
    --manual) MODE="manual" ;;
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) usage; exit 2 ;;
esac

if [[ ${EUID} -ne 0 ]]; then
    echo "Este script necesita root. Ejecútalo así:"
    echo "  sudo $0 ${1:-}"
    exit 1
fi

WIFI_DIR="$SCRIPT_DIR/src/USB/driver_fw/drivers/aic8800"
BT_DIR="$SCRIPT_DIR/src/USB/driver_fw/drivers/aic_btusb"
LOAD_KO="$WIFI_DIR/aic_load_fw/aic_load_fw.ko"
DRV_KO="$WIFI_DIR/aic8800_fdrv/aic8800_fdrv.ko"
BT_KO="$BT_DIR/aic_btusb.ko"
FW_SRC="$SCRIPT_DIR/src/USB/driver_fw/fw"

check_build() {
    local missing=0 f
    for f in "$LOAD_KO" "$DRV_KO" "$BT_KO"; do
        if [[ ! -f "$f" ]]; then
            echo "Falta: $f"
            missing=1
        fi
    done
    if (( missing )); then
        echo
        echo "Compila primero con:"
        echo "  make -C '$WIFI_DIR' LLVM=1 -j\$(nproc)"
        echo "  make -C '$BT_DIR' LLVM=1 -j\$(nproc)"
        exit 1
    fi
}

install_firmware() {
    echo "==> Instalando firmware en /lib/firmware/aic8800_fw/USB"
    install -d -m 755 /lib/firmware/aic8800_fw/USB
    cp -a "$FW_SRC/." /lib/firmware/aic8800_fw/USB/
}

install_config() {
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
}

reload_modules() {
    echo "==> Cargando módulos"
    local m
    set +e
    # Descargar versiones previas (si existen)
    for m in aic_btusb aic8800_fdrv aic_load_fw; do
        modprobe -r "$m" 2>/dev/null
    done
    # Si btusb ya capturó la interfaz Bluetooth, soltarla.
    modprobe -r btusb 2>/dev/null

    echo "    aic_load_fw (descarga de firmware WiFi)"
    modprobe aic_load_fw
    sleep 2
    echo "    aic8800_fdrv (WiFi)"
    modprobe aic8800_fdrv
    echo "    aic_btusb (Bluetooth)"
    modprobe aic_btusb

    systemctl enable --now bluetooth 2>/dev/null
    set -e

    # Esperar a que aparezca la interfaz inalámbrica (máx. 15 s)
    local i
    for i in $(seq 1 15); do
        if compgen -G "/sys/class/net/wlan*" >/dev/null 2>&1 || \
           compgen -G "/sys/class/net/wlp*"  >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
}

show_status() {
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
}

check_build
install_firmware
install_config

if [[ "$MODE" == "dkms" ]]; then
    if ! command -v dkms >/dev/null 2>&1; then
        echo "==> dkms no está instalado; instalando desde los repos..."
        pacman -S --needed --noconfirm dkms
    fi

    VER="1.0.0"
    DEST="/usr/src/aic8800-usb-$VER"

    echo "==> Preparando fuente DKMS en $DEST"
    rm -rf "$DEST"
    install -d -m 755 "$DEST"
    cp -a "$SCRIPT_DIR/src/USB" "$DEST/USB"

    # No llevar binarios de la compilación manual a la fuente DKMS
    make -C "$DEST/USB/driver_fw/drivers/aic8800" clean >/dev/null 2>&1 || true
    make -C "$DEST/USB/driver_fw/drivers/aic_btusb" clean >/dev/null 2>&1 || true

    cat > "$DEST/dkms.conf" <<'EOF'
PACKAGE_NAME="aic8800-usb"
PACKAGE_VERSION="1.0.0"

MAKE[0]="make -C $kernel_source_dir M=$dkms_tree/$PACKAGE_NAME/$PACKAGE_VERSION/build/USB/driver_fw/drivers/aic8800 LLVM=1 && make -C $kernel_source_dir M=$dkms_tree/$PACKAGE_NAME/$PACKAGE_VERSION/build/USB/driver_fw/drivers/aic_btusb LLVM=1"
CLEAN="make -C $kernel_source_dir M=$dkms_tree/$PACKAGE_NAME/$PACKAGE_VERSION/build/USB/driver_fw/drivers/aic8800 clean; make -C $kernel_source_dir M=$dkms_tree/$PACKAGE_NAME/$PACKAGE_VERSION/build/USB/driver_fw/drivers/aic_btusb clean"

BUILT_MODULE_NAME[0]="aic_load_fw"
BUILT_MODULE_LOCATION[0]="USB/driver_fw/drivers/aic8800/aic_load_fw"
DEST_MODULE_LOCATION[0]="/updates/dkms"

BUILT_MODULE_NAME[1]="aic8800_fdrv"
BUILT_MODULE_LOCATION[1]="USB/driver_fw/drivers/aic8800/aic8800_fdrv"
DEST_MODULE_LOCATION[1]="/updates/dkms"

BUILT_MODULE_NAME[2]="aic_btusb"
BUILT_MODULE_LOCATION[2]="USB/driver_fw/drivers/aic_btusb"
DEST_MODULE_LOCATION[2]="/updates/dkms"

AUTOINSTALL="yes"
EOF

    dkms remove -m aic8800-usb -v "$VER" --all 2>/dev/null || true
    dkms add -m aic8800-usb -v "$VER"

    echo "==> Compilando e instalando con DKMS para $KVER"
    dkms build  -m aic8800-usb -v "$VER" -k "$KVER"
    dkms install -m aic8800-usb -v "$VER" -k "$KVER" --force

    # Quitar copia manual si existía, para no tener módulos duplicados
    rm -rf "/lib/modules/$KVER/updates/aic8800"
    depmod -a "$KVER"
else
    echo "==> Instalando módulos en /lib/modules/$KVER/updates/aic8800"
    install -d -m 755 "/lib/modules/$KVER/updates/aic8800"
    install -m 644 "$LOAD_KO" "$DRV_KO" "$BT_KO" "/lib/modules/$KVER/updates/aic8800/"
    depmod -a "$KVER"
fi

reload_modules
show_status

echo
echo "Listo. Si la WiFi/Bluetooth no aparece, revisa el estado anterior y"
echo "prueba un reinicio: sudo reboot"
