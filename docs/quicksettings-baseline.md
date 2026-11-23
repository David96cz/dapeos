# Quick settings – baseline měření (23. 11. 2026)

Větev: `refactor/quicksettings`, commit s trace instrumentací.
Log: `/tmp/dapeos-qs-trace.log` (1985 řádků, 129 kB, 283 s záznamu).

## Souhrn

- 1641 spuštěných externích příkazů za 283 s.
- 153 cyklů `update-tiles`, tedy přibližně každé 2 s, i když bylo okno skryté.
- Jeden cyklus `update-tiles` běžně 80–120 ms, na Bluetooth stránce 400–500 ms.
- Start: `main-start` → `build-ui-end` 127 ms; první data (`update-tiles-end`) 662 ms.
- Bluetooth stránka: `bt-refresh-start` → `bt-list-done` 8,6 s (scan + 5s timeout).
- WiFi scan: `wifi-scan-start` → `wifi-scan-done` 2,8–32 s; `nmcli ... wifi list` max 3,87 s.
- `nmcli -t -f ACTIVE,SSID device wifi list`: 107 volání, průměr 128 ms, max 3,87 s.
- `bluetoothctl info`: 99+ volání pro AirPody, 20–45 ms každé; další desítky pro okolní zařízení.

## Hlavní příčiny

1. `update_tiles` je globální 2s timer a běží i při skrytém okně.
2. Každý tik dělá několik synchronních subprocessů: rfkill, bluetoothctl show/devices/info, nmcli radio/device status/active wifi list.
3. Bluetooth refresh používá `bluetoothctl --timeout 5 scan on` a čeká 5,5 s; seznam se mezitím celý maže.
4. WiFi refresh používá rescan + 3s timer; seznam se maže a znovu plní.
5. Všechny příkazy blokují GTK hlavní vlákno, takže toggle a překreslení čekají.

## Cílové hodnoty po optimalizaci

- Skryté okno: 0 externích příkazů.
- Viditelná hlavní stránka: 1 tik < 50 ms, bez blokování UI.
- Bluetooth refresh: první výsledek < 300 ms, inkrementální update, žádné mazání seznamu.
- WiFi refresh: první výsledek < 300 ms, skutečný scan max 1× za 5 s.
- Toggle: vizuální reakce < 50 ms, výsledek asynchronně.
