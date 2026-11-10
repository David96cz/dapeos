# Architektura

## Tok instalace

```
dapeos.sh
  └─ main()
       ├─ init_script        globální proměnné (uživatel, cesty, jazyk)
       ├─ init_setup         interaktivní volby
       ├─ prepare_system     základ systému
       ├─ install_packages   balíčky podle configu
       ├─ setup_auto_updates
       ├─ configure_xfce     nebo configure_lxqt / configure_plasma
       ├─ setup_display_manager
       ├─ setup_boot         GRUB + Plymouth
       └─ admin_security     účty, práva, profil
```

## Vrstvy

- **`dapeos.sh`** – pouze vstupní bod: načte moduly, zpracuje argumenty,
  zavolá `main`.
- **`lib/`** – funkce nezávislé na desktopu. Logování, konfigurace, balíčky,
  boot, práce s `.desktop` soubory.
- **`modules/`** – konkrétní desktopová prostředí. `modules/xfce/` je
  rozdělené podle oblasti (panel, vzhled, aplikace, session, doplňky).
- **`contents/`** – data: konfigurace, skripty, ikony, binárky.

## Konvence

- Funkce: `snake_case`, prefix podle oblasti (`xfce_`, `plymouth_`, `desktop_`).
- Každý soubor začíná `#!/bin/bash` a `# shellcheck shell=bash`.
- Logování: `log` (info), `warn` (varování), `die` (chyba + exit).
- Práce s `.desktop`: vždy přes `desktop_*` helpery, nikdy ruční `sed`.
- Autostart: pouze přes `[AUTORUN]` v configu a `autostart_sync`.
- Cesty: vždy přes `$CONTENTS_DIR`, `$USER_HOME`, `$BASE_DIR`.

## Zdrojové načítání

`dapeos.sh` načítá soubory v pevném pořadí; funkce se volají až po načtení
všech modulů. Žádný modul nesmí mít top-level vedlejší efekt kromě definic
proměnných.

## Testování

- `bash scripts/lint.sh` – syntaxe, shellcheck, Python.
- Testovací instalace na VM: `sudo bash dapeos.sh --no-reboot`.
- Log: `/var/log/dapeos-install.log`.

## Co je legacy

`modules/lxqt.sh` a `modules/plasma.sh` zůstávají pro historii. Aktivně se
nevyvíjejí; `modules/xfce/` je jediná podporovaná větev.
