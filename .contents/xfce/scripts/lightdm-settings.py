#!/usr/bin/env python3
import sys
import os
import subprocess
import configparser
from PyQt5.QtWidgets import (QApplication, QWidget, QVBoxLayout, QHBoxLayout,
                             QLineEdit, QPushButton, QMessageBox, QLabel, 
                             QCheckBox, QFileDialog, QColorDialog)
from PyQt5.QtCore import Qt, QThread, pyqtSignal

# Cesta pro ukládání stavu aplikace do uživatelského profilu
CONFIG_FILE = os.path.expanduser("~/.config/lightdm-wallpaper-setter.conf")
DEFAULT_WALLPAPER = "/usr/share/backgrounds/wallpaper.png"

# --- VLÁKNO PRO ZÁPIS KONFIGURACE S PRÁVY ROOT ---
class LightDMWorker(QThread):
    finished = pyqtSignal(int, str)

    def __init__(self, wallpaper_path, bg_color, draw_user):
        super().__init__()
        self.wallpaper_path = wallpaper_path
        self.bg_color = bg_color
        self.draw_user = draw_user

    def run(self):
        draw_user_str = "true" if self.draw_user else "false"
        
        # Vytvoříme override konfiguraci s NEJVYŠŠÍ prioritou (99).
        # SPRÁVNÝ klíč pro zakázání crossfadu uživatelské tapety je user-background.
        cmd = f"""
        mkdir -p /etc/lightdm/lightdm-gtk-greeter.conf.d
        cat << 'EOF' > /etc/lightdm/lightdm-gtk-greeter.conf.d/99_custom.conf
[greeter]
background={self.wallpaper_path}
background-color={self.bg_color}
user-background={draw_user_str}
EOF
        """
        
        sudo_bin = None
        for b in ["lxqt-sudo", "pkexec", "gksudo"]:
            if subprocess.run(["which", b], stdout=subprocess.DEVNULL).returncode == 0:
                sudo_bin = b
                break
                
        if not sudo_bin:
            self.finished.emit(1, "Chybí grafický nástroj pro zadání hesla správce (lxqt-sudo, pkexec)!")
            return

        result = subprocess.run([sudo_bin, "bash", "-c", cmd])
        self.finished.emit(result.returncode, "")


# --- HLAVNÍ OKNO APLIKACE ---
class LightDMWallpaperSetter(QWidget):
    def __init__(self):
        super().__init__()
        self.worker = None
        
        # Výchozí hodnoty stavu
        self.selected_color = "#2a7fca"
        self.draw_user_state = True
        self.saved_path = DEFAULT_WALLPAPER

        self.load_app_state() # Načtení předchozího stavu ze souboru
        self.initUI()
        self.apply_initial_state()

    def initUI(self):
        self.setWindowTitle('Nastavení zamykací obrazovky')
        self.setFixedSize(550, 360)
        self.setWindowFlags(Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint)
        
        self.setStyleSheet("""
            QWidget { background-color: #f5f5f5; font-family: sans-serif; }
            QLabel { color: #333; }
            QLineEdit { padding: 10px; border: 1px solid #ccc; border-radius: 5px; background-color: white; font-size: 11pt; }
            QCheckBox { font-size: 11pt; padding: 5px; }
            QPushButton { background-color: #e0e0e0; color: #222; padding: 10px; border: 1px solid #ccc; border-radius: 5px; font-size: 10pt; }
            QPushButton:hover { background-color: #d5d5d5; }
            QPushButton:disabled { background-color: #e0e0e0; color: #9e9e9e; border: 1px solid #d5d5d5; }
            QPushButton#btnSave { background-color: #2a7fca; color: white; padding: 15px; font-weight: bold; border-radius: 5px; font-size: 12pt; border: none; }
            QPushButton#btnSave:hover { background-color: #1e63a1; }
            QPushButton#btnSave:disabled { background-color: #9e9e9e; color: #e0e0e0; }
        """)

        layout = QVBoxLayout()
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(20)
        
        lbl_info = QLabel("<b>Správce přihlašovací obrazovky</b><br>Nastavte si vzhled vašeho lockscreenu.")
        lbl_info.setStyleSheet("font-size: 12pt;")
        layout.addWidget(lbl_info)

        # Sekce pro ruční výběr tapety
        layout_wallpaper = QHBoxLayout()
        self.txt_path = QLineEdit()
        self.txt_path.setPlaceholderText("Cesta k souboru s tapetou...")
        
        self.btn_browse = QPushButton("Procházet...")
        self.btn_browse.setCursor(Qt.PointingHandCursor)
        self.btn_browse.clicked.connect(self.browse_wallpaper)
        
        layout_wallpaper.addWidget(self.txt_path)
        layout_wallpaper.addWidget(self.btn_browse)
        layout.addLayout(layout_wallpaper)

        # Výběr podkladové barvy
        layout_color = QHBoxLayout()
        lbl_color_text = QLabel("Jednolitá barva pozadí (při načítání):")
        lbl_color_text.setStyleSheet("font-size: 11pt;")
        
        self.btn_color = QPushButton("Vybrat barvu")
        self.btn_color.setCursor(Qt.PointingHandCursor)
        self.btn_color.setStyleSheet(f"background-color: {self.selected_color}; color: white; font-weight: bold;")
        self.btn_color.clicked.connect(self.pick_color)
        
        layout_color.addWidget(lbl_color_text)
        layout_color.addWidget(self.btn_color)
        layout.addLayout(layout_color)

        # Vykreslovat tapety uživatelů
        self.chk_draw_user = QCheckBox("Měnit pozadí dynamicky podle vybraného uživatele")
        self.chk_draw_user.setChecked(self.draw_user_state)
        layout.addWidget(self.chk_draw_user)

        layout.addStretch()
        
        self.btn_save = QPushButton('Uložit nastavení a aplikovat')
        self.btn_save.setObjectName("btnSave")
        self.btn_save.setCursor(Qt.PointingHandCursor)
        self.btn_save.clicked.connect(self.handle_save)
        layout.addWidget(self.btn_save)
        
        self.setLayout(layout)

    def load_app_state(self):
        """Načte stav z konfiguračního souboru .conf uživatele."""
        if os.path.exists(CONFIG_FILE):
            try:
                config = configparser.ConfigParser()
                config.read(CONFIG_FILE)
                if 'State' in config:
                    self.draw_user_state = config['State'].getboolean('DrawUser', True)
                    self.selected_color = config['State'].get('BgColor', "#2a7fca")
                    # Pokud si minule uložil vlastní cestu, načte ji. Jinak použije default.
                    self.saved_path = config['State'].get('WallpaperPath', DEFAULT_WALLPAPER)
            except:
                pass

    def save_app_state(self):
        """Uloží aktuální stav UI prvků do souboru."""
        try:
            os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
            config = configparser.ConfigParser()
            config['State'] = {
                'DrawUser': str(self.chk_draw_user.isChecked()),
                'BgColor': self.selected_color,
                'WallpaperPath': self.txt_path.text()
            }
            with open(CONFIG_FILE, 'w') as f:
                config.write(f)
        except:
            pass

    def apply_initial_state(self):
        """Aplikuje načtené stavy (naplní cestu a nastaví barvu tlačítka)."""
        self.txt_path.setText(self.saved_path)
        self.btn_color.setStyleSheet(f"background-color: {self.selected_color}; color: white; font-weight: bold;")

    def browse_wallpaper(self):
        # 1. Zjistíme, co je aktuálně v textovém poli
        current_path = self.txt_path.text().strip()
        
        # 2. Určíme výchozí složku pro otevření dialogu
        start_dir = "/usr/share/backgrounds"
        if current_path:
            if os.path.exists(current_path):
                # Pokud cesta existuje a je to soubor, vezmeme jeho složku
                start_dir = os.path.dirname(current_path) if os.path.isfile(current_path) else current_path
            elif os.path.exists(os.path.dirname(current_path)):
                # Pokud soubor neexistuje, ale složka ano (např. překlep), otevřeme aspoň tu složku
                start_dir = os.path.dirname(current_path)

        # 3. Otevřeme dialog se správnou počáteční cestou (start_dir)
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Vybrat tapetu pro LightDM", start_dir, "Obrázky (*.png *.jpg *.jpeg)"
        )
        
        if file_path:
            self.txt_path.setText(file_path)


    def pick_color(self):
        color = QColorDialog.getColor()
        if color.isValid():
            self.selected_color = color.name()
            self.btn_color.setStyleSheet(f"background-color: {self.selected_color}; color: white; font-weight: bold;")

    def handle_save(self):
        path = self.txt_path.text().strip()
        
        if not path:
            QMessageBox.warning(self, "Chyba", "Prosím, zadejte cestu k tapetě.")
            return
            
        if not os.path.exists(path):
            QMessageBox.warning(self, "Chyba", "Zvolený soubor s tapetou neexistuje.")
            return
            
        self.btn_save.setDisabled(True)
        self.btn_save.setText("Aplikuji nastavení...")
        
        # Uložíme si stav aplikace lokálně
        self.save_app_state()
        
        # Spuštění zápisu do LightDM konfigurace na pozadí
        self.worker = LightDMWorker(path, self.selected_color, self.chk_draw_user.isChecked())
        self.worker.finished.connect(self.on_save_finished)
        self.worker.start()

    def on_save_finished(self, returncode, error_msg):
        self.btn_save.setDisabled(False)
        self.btn_save.setText("Uložit nastavení a aplikovat")
        
        if returncode == 0:
            QMessageBox.information(self, "Úspěch", "Nastavení bylo úspěšně uloženo.")
        else:
            msg = error_msg if error_msg else "Nepodařilo se uložit konfiguraci (chyba oprávnění)."
            QMessageBox.critical(self, "Chyba", msg)

if __name__ == '__main__':
    app = QApplication(sys.argv)
    ex = LightDMWallpaperSetter()
    ex.show()
    sys.exit(app.exec_())
