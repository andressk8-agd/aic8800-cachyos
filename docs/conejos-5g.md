# Conexión WiFi a `Conejos_5G` con AIC8800D80

Caso documentado en CachyOS con kernel `7.3.3-1-cachyos` (x86_64) y el combo
**AIC8800D80** (`a69c:8d80`). El AP `Conejos_5G` anuncia `WPA2 WPA3`; el
firmware del AIC8800 no completa la asociación en modo SAE (WPA3).

## Síntoma

`nmcli device wifi list` muestra el AP como `WPA2 WPA3`:

```text
IN-USE  SSID        BSSID              CHAN  FREQ      RATE         SIGNAL  SECURITY
*       Conejos_5G  0C:F0:7B:21:DD:DD  100   5500 MHz  270 Mbit/s   59      WPA2 WPA3
```

NetworkManager elige `SAE FT-SAE` y `wpa_supplicant` repite el rechazo:

```text
NetworkManager: Config: added 'key_mgmt' value 'SAE FT-SAE'
wpa_supplicant: wlan0: CTRL-EVENT-ASSOC-REJECT bssid=00:00:00:00:00:00 status_code=1
```

`status_code=1` es un fallo no especificado: la asociación nunca se completa y
la conexión entra en bucle.

## Diagnóstico

```bash
nmcli -f IN-USE,SSID,BSSID,CHAN,FREQ,RATE,SIGNAL,SECURITY device wifi list
journalctl -b -u NetworkManager | grep -iE 'SAE|ASSOC-REJECT|status_code'
nmcli -f 802-11-wireless-security.key-mgmt,802-11-wireless-security.pmf \
    connection show Conejos_5G
```

Si aparece `key_mgmt 'SAE FT-SAE'` junto a
`ASSOC-REJECT ... status_code=1`, el driver/firmware está intentando WPA3.
La solución es forzar **WPA2-PSK** en el perfil.

## Ajustes aplicados

```bash
nmcli connection modify 'Conejos_5G' \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.pmf 1
nmcli connection up 'Conejos_5G'
```

- `wifi-sec.key-mgmt wpa-psk`: fuerza WPA2-PSK (RSN/CCMP) en lugar de SAE.
- `wifi-sec.pmf 1`: desactiva PMF (*Protected Management Frames*), que este
  firmware tampoco negocia bien con este AP.

> Esto reinicia la conexión WiFi. No lo ejecutes por SSH sin acceso alternativo
> (Ethernet, consola local u otra red).

Valores finales del perfil (la contraseña no se muestra ni se guarda en el
repositorio):

| Propiedad | Valor |
|---|---|
| `connection.id` | `Conejos_5G` |
| `connection.interface-name` | `wlan0` |
| `connection.autoconnect` | `yes` |
| `802-11-wireless.ssid` | `Conejos_5G` |
| `802-11-wireless.mode` | `infrastructure` |
| `802-11-wireless.band` | automático (`--`) |
| `802-11-wireless.channel` | `0` (automático) |
| `802-11-wireless.hidden` | `no` |
| `802-11-wireless.powersave` | `0` (default) |
| `802-11-wireless-security.key-mgmt` | `wpa-psk` |
| `802-11-wireless-security.pmf` | `1` (disable) |
| `802-11-wireless-security.auth-alg` | `open` |
| `802-11-wireless-security.proto` | default (`rsn`) |
| `802-11-wireless-security.pairwise` | default (`ccmp`) |
| `802-11-wireless-security.group` | default (`ccmp`) |
| `ipv4.method` | `auto` |
| `ipv6.method` | `auto` |

La PSK queda almacenada por NetworkManager en
`/etc/NetworkManager/system-connections/` (solo root). Este documento y los
scripts no la leen, no la imprimen y no la incluyen.

## Verificación

```text
$ iw dev wlan0 link
Connected to 0c:f0:7b:21:dd:dd (on wlan0)
        SSID: Conejos_5G
        freq: 5500.0
        signal: -65 dBm
        rx bitrate: 360.3 MBit/s 80MHz HE-MCS 7 HE-NSS 1 HE-GI 0 HE-DCM 0
        tx bitrate: 288.2 MBit/s 80MHz HE-MCS 5 HE-NSS 1 HE-GI 0 HE-DCM 0
```

Pruebas realizadas con el tráfico forzado por `wlan0`:

```text
$ ip -4 -br addr show wlan0
wlan0  UP  192.168.40.87/24

$ ping -I wlan0 -c 4 192.168.40.1
4 packets transmitted, 4 received, 0% packet loss
rtt min/avg/max/mdev = 1.111/6.366/20.650/8.252 ms

$ curl --interface wlan0 -o /dev/null \
    'https://speed.cloudflare.com/__down?bytes=10000000'
HTTP 200, 10000000 bytes, 0.543 s, 18.4 MB/s (~147 Mbit/s)
```

- Canal 100 (5500 MHz), 80 MHz, WiFi 6 (HE-MCS 7).
- DHCP IPv4/IPv6 automático.
- La ruta por defecto de Ethernet tiene métrica 100 y la de WiFi 600; las
  pruebas se forzaron con `-I wlan0` / `--interface wlan0`.

## Reversión

Si una versión futura del firmware corrige SAE:

```bash
nmcli connection modify 'Conejos_5G' \
    wifi-sec.key-mgmt sae \
    wifi-sec.pmf 2
nmcli connection up 'Conejos_5G'
```

`pmf 2` es opcional y `pmf 3` obligatorio. No se recomienda volver a SAE con la
versión actual del driver.

## Script

[`scripts/forzar-wpa2-psk.sh`](../scripts/forzar-wpa2-psk.sh) aplica los dos
ajustes a cualquier perfil existente:

```bash
./scripts/forzar-wpa2-psk.sh Conejos_5G
```
