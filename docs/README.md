# DapeOS

Post-instalační konfigurátor, který udělá z čistého Debianu (netinst) použitelný
systém pro člověka přicházejícího z Windows – s XFCE, českým prostředím,
přednastavenými aplikacemi a chováním, na které je zvyklý.

![náhled](https://github.com/user-attachments/assets/64951e8f-3912-4ba0-9bc4-acdc5192d50c)

## Co to umí

- **XFCE jako Windows** – panel dole, Whisker menu, tmavý režim, tapeta, ikony
- **Aplikace** – prohlížeč, kancelářský balík, multimédia, ZIP/RAR, tiskárny
- **Windows zvyky** – klávesové zkratky (Win+E, Win+L, Ctrl+Alt+Del…), názvy aplikací
- **Albert** – vyhledávač spuštění (obdoba Windows Search)
- **Aktualizace** – správce aktualizací s tray ikonou a automatickou kontrolou
- **Uvítání** – první přihlášení s průvodcem
- **Boot** – tichý GRUB a grafický Plymouth (volitelně)
- **Panel ikony** – barevné ikony ve tmavém i světlém režimu, plynulé škálování

## Požadavky

- Čerstvá instalace Debianu 13 (trixie), **bez desktopového prostředí**
- Během instalace Debianu zvolte pouze „standardní systémové nástroje“
- 64bitový procesor (amd64 nebo arm64), 2 GB RAM, připojení k internetu

## Instalace

```bash
sudo apt install git -y
git clone https://github.com/David96cz/dapeos
cd dapeos
sudo bash dapeos.sh
```

Skript se zeptá na desktop, prohlížeč, kancelářský balík a automatické
přihlášení. Poté nainstaluje a nakonfiguruje systém a restartuje počítač.

Pro testování bez restartu:

```bash
sudo bash dapeos.sh --no-reboot
```

Průběh se loguje do `/var/log/dapeos-install.log`.

## Struktura projektu

```
dapeos.sh              vstupní bod, main(), argumenty
lib/                   společné funkce
  init.sh              globální proměnné, interaktivní setup
  common.sh            log, chyby, konfigurace
  system.sh            balíčky, služby, hardware
  boot.sh              GRUB, Plymouth
  desktop.sh           .desktop soubory, autostart
modules/               desktopová prostředí
  xfce/                XFCE (podporované)
  lxqt.sh              LXQt (legacy)
  plasma.sh            KDE Plasma (legacy)
contents/              data instalace
  install.conf     volby instalace a seznam balíčků
  xfce/                konfigurace, skripty, ikony, binárky
```

Podrobnosti: [Architektura](docs/ARCHITECTURE.md) a [Konfigurace](docs/CONFIG.md).

## Vývoj

```bash
bash scripts/lint.sh
```

Kontroluje syntaxi shellu, shellcheck (pokud je nainstalovaný) a Python.

## Licence

Zatím bez licence – před zveřejněním doplnit.
