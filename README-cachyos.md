# Driver AIC8800 (WiFi 6 + Bluetooth) en CachyOS / Linux 7.3

Tarjeta detectada:

```
02:00.0 Network controller [0280]: Device [a69c:8d80]
Bus 001 Device 004: ID a69c:8d80 aicsemi AIC Wlan
```

Es un combo **AIC8800D80** (WiFi + Bluetooth por USB). No hay driver en el
kernel principal, así que se usa el driver out-of-tree de Radxa/AIC.

## Por qué hizo falta parchear

El kernel de CachyOS está compilado con **clang + LTO**, y el kernel 7.3 cambió
la API de cfg80211 (`net_device` → `wireless_dev`, cookies de RoC, etc.). El
código original no compila tal cual.

Solución aplicada en este árbol:

1. Normalizar a LF dos archivos que venían con CRLF (`aicbluetooth.c`,
   `aic_bluetooth_main.c`).
2. Aplicar la serie oficial de parches de Radxa (`debian/patches/series`),
   que incluye `fix-linux-7.1-build.patch`, `fix-linux-7.2-build.patch` y
   `fix-linux-7.3-build.patch`.
3. Compilar con `LLVM=1` (clang/LLD), no con gcc.

Los cambios están en la rama local `cachyos-7.3`.

## Compilar

```bash
cd ~/Projects/aic8800
./build.sh
```

Equivale a:

```bash
make -C src/USB/driver_fw/drivers/aic8800  LLVM=1 -j$(nproc)
make -C src/USB/driver_fw/drivers/aic_btusb LLVM=1 -j$(nproc)
```

## Instalar

Instalación para el kernel actual:

```bash
sudo ./install.sh
```

Instalación recomendada con DKMS (se recompila sola en cada actualización de
kernel):

```bash
sudo ./install.sh --dkms
```

El instalador hace:

- copia el firmware a `/lib/firmware/aic8800_fw/USB/`
- instala `aic_load_fw.ko`, `aic8800_fdrv.ko` y `aic_btusb.ko`
- ejecuta `depmod`
- crea `/etc/modules-load.d/aic8800.conf`
- crea `/etc/modprobe.d/aic8800.conf` (da prioridad a `aic_btusb` sobre `btusb`)
- carga los módulos y habilita `bluetooth`

## Verificar

```bash
ip -br link                 # debe aparecer wlan0
rfkill list                 # WiFi/Bluetooth no bloqueados
bluetoothctl list           # debe aparecer un controlador
dmesg | grep -iE 'aic|8800|hci'
```

## Si algo falla

WiFi:

```bash
dmesg | grep -i aic
ls /lib/firmware/aic8800_fw/USB/aic8800D80/
modinfo aic8800_fdrv
```

Bluetooth:

```bash
lsmod | grep -E 'btusb|aic'
sudo modprobe -r btusb
sudo modprobe aic_btusb
bluetoothctl list
```

Si `btusb` vuelve a capturar la interfaz, el `softdep` de
`/etc/modprobe.d/aic8800.conf` debería evitarlo tras reiniciar.

## Actualizaciones de kernel

- Con DKMS: no hay que hacer nada; DKMS recompila al instalar el nuevo kernel.
- Sin DKMS: volver a ejecutar `./build.sh && sudo ./install.sh` después de
  cada actualización de `linux-cachyos`.

## Referencias

- Driver base: <https://github.com/radxa-pkg/aic8800>
- Parches 7.x incluidos en `debian/patches/`
