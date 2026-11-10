# Konfigurace

Instalace se řídí dvěma soubory. Oba používají formát INI: sekce v hranatých
závorkách, hodnoty po řádcích, `#` na začátku řádku je komentář.

## `contents/install.conf` – volby instalace

### `[SETTINGS]`

| Klíč | Hodnoty | Význam |
|---|---|---|
| `GRUB_TIMEOUT` | číslo | prodleva boot menu (0 = bez menu) |
| `BOOT_LOGO` | `TRUE` / `FALSE` | grafický start přes Plymouth |
| `CONFIRM_LOGOUT` | `TRUE` / `FALSE` | potvrzování odhlášení |

### `[INSTALL]`

Seznam balíčků k instalaci, oddělený mezerami nebo novými řádky.
Komentáře začínají `#`.

```
[INSTALL]
xorg network-manager upower
vlc featherpad
```

## `contents/xfce/xfce.conf` – chování XFCE

### `[CORE_PACKAGES]`

Balíčky nutné pro prostředí. Instalují se vždy.

### `[EXTRA_PACKAGES]`

Doplňkové aplikace a nástroje.

### `[APPS_TO_HIDE]`

`.desktop` soubory, které se mají skrýt z menu (nastaví se `NoDisplay=true`).
Soubory se nejdřív zkopírují do `~/.local/share/applications`.

### `[UNREMOVABLE]`

Aplikace, které nepůjdou odinstalovat (zapisuje se do
`/etc/dapeos-unremovable.txt`, čte odinstalátor).

### `[AUTORUN]`

Aplikace spouštěné po přihlášení. Jeden příkaz na řádek, může obsahovat
argumenty:

```
[AUTORUN]
albert-sync
win-titles
dapeos-panel-watch
dapeos-welcome --first-run
```

Z každého řádku se vygeneruje `~/.config/autostart/<nazev>.desktop`
s `Exec=` přesně podle configu.

## Přidání položky

1. Uprav příslušnou sekci v `contents/xfce/xfce.conf`.
2. Spusť instalaci (nebo jen příslušnou část) znovu.
3. U autostartu zkontroluj `~/.config/autostart/`.

## Poznámky

- Hodnoty se neořezávají o uvozovky – piš je bez nich.
- Windows konce řádků (`\r`) se automaticky odstraňují.
- Pořadí sekcí nemá vliv.
