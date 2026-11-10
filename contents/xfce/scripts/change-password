#!/usr/bin/env python3
import sys
import os
import subprocess
import pexpect
import base64
import pwd
from PyQt5.QtWidgets import (QApplication, QWidget, QVBoxLayout, QFormLayout, 
                             QLineEdit, QPushButton, QMessageBox, QCheckBox)
from PyQt5.QtCore import Qt

class PasswordChanger(QWidget):
    def __init__(self):
        super().__init__()
        
        # 1. Zjištění, kdo aplikaci fyzicky spouští (ty)
        try:
            self.running_user = os.getlogin()
        except:
            self.running_user = pwd.getpwuid(os.getuid()).pw_name
            
        # 2. Zjištění, komu se heslo mění (podvrženo z user-manageru)
        self.user_name = os.environ.get("SUDO_USER", self.running_user)
        
        if self.user_name == "root":
            users = [u.pw_name for u in pwd.getpwall() if 1000 <= u.pw_uid < 65000]
            if users:
                self.user_name = users[0]

        # Pokud se mění cizí heslo, jde o Admin reset (nepotřebujeme staré heslo)
        self.is_admin_reset = (self.user_name != self.running_user)

        # 3. Spočítání běžných uživatelů pro skrytí Autologinu
        normal_users = [u for u in pwd.getpwall() if 1000 <= u.pw_uid < 65000]
        self.has_multiple_users = len(normal_users) > 1

        self.autologin_conf = "/etc/lightdm/lightdm.conf.d/autologin.conf"
        self.initUI()

    def initUI(self):
        self.setWindowTitle(f'Změna hesla pro: {self.user_name}')
        self.setFixedSize(420, 310 if not self.is_admin_reset else 270)
        self.setWindowFlags(Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint)
        
        layout = QVBoxLayout()
        form_layout = QFormLayout()
        
        self.old_pass = QLineEdit()
        self.old_pass.setEchoMode(QLineEdit.Password)
        self.old_pass.setPlaceholderText("Prázdné, pokud heslo není nastaveno...")
        
        self.new_pass = QLineEdit()
        self.new_pass.setEchoMode(QLineEdit.Password)
        self.new_pass.setPlaceholderText("Nechte prázdné pro zrušení hesla")
        
        self.new_pass_confirm = QLineEdit()
        self.new_pass_confirm.setEchoMode(QLineEdit.Password)

        # Zobrazíme "Stávající heslo" POUZE pokud si měníš heslo sobě
        if not self.is_admin_reset:
            form_layout.addRow('Stávající heslo:', self.old_pass)
            
        form_layout.addRow('Nové heslo:', self.new_pass)
        form_layout.addRow('Potvrdit nové heslo:', self.new_pass_confirm)

        layout.addLayout(form_layout)

        self.cb_show_pass = QCheckBox('Zobrazit nová hesla')
        self.cb_show_pass.stateChanged.connect(self.toggle_echo_mode)
        layout.addWidget(self.cb_show_pass)

        # Autologin checkbox se vytvoří jen tehdy, pokud je počítač pro 1 osobu
        if not self.has_multiple_users:
            self.cb_autologin = QCheckBox('Automatické přihlášení (bez hesla při startu)')
            if os.path.exists(self.autologin_conf):
                self.cb_autologin.setChecked(True)
            self.cb_autologin.stateChanged.connect(self.toggle_autologin)
            layout.addWidget(self.cb_autologin)
        else:
            self.cb_autologin = None

        btn_text = 'Uložit heslo' if not self.is_admin_reset else 'Vynutit změnu hesla'
        self.btn_save = QPushButton(btn_text)
        self.btn_save.setStyleSheet("background-color: #2a7fca; color: white; padding: 10px; font-weight: bold; border-radius: 5px;")
        self.btn_save.setCursor(Qt.PointingHandCursor)
        self.btn_save.clicked.connect(self.handle_change)
        
        layout.addSpacing(10)
        layout.addWidget(self.btn_save)
        self.setLayout(layout)

    def toggle_echo_mode(self, state):
        if state == Qt.Checked:
            self.new_pass.setEchoMode(QLineEdit.Normal)
            self.new_pass_confirm.setEchoMode(QLineEdit.Normal)
        else:
            self.new_pass.setEchoMode(QLineEdit.Password)
            self.new_pass_confirm.setEchoMode(QLineEdit.Password)

    def toggle_autologin(self, state):
        conf_dir = "/etc/lightdm/lightdm.conf.d"
        if state == Qt.Checked:
            cmd = f"mkdir -p {conf_dir} && echo -e '[Seat:*]\\nautologin-user={self.user_name}\\nautologin-user-timeout=0' > {self.autologin_conf}"
            try:
                subprocess.run(['pkexec', 'bash', '-c', cmd], check=True)
                QMessageBox.information(self, "Nastavení", "Autologin ZAPNUT. Počítač půjde rovnou na plochu.")
            except Exception as e:
                QMessageBox.critical(self, "Chyba", f"Nepodařilo se zapnout.\n{e}")
                self.cb_autologin.blockSignals(True)
                self.cb_autologin.setChecked(False)
                self.cb_autologin.blockSignals(False)
        else:
            cmd = f"rm -f {self.autologin_conf} && sed -i '/^[[:space:]]*autologin-user[[:space:]]*=/d' /etc/lightdm/lightdm.conf 2>/dev/null || true"
            try:
                subprocess.run(['pkexec', 'bash', '-c', cmd], check=True)
                QMessageBox.information(self, "Nastavení", "Autologin VYPNUT. Heslo bude striktně vyžadováno.")
            except Exception as e:
                QMessageBox.critical(self, "Chyba", f"Nepodařilo se vypnout.\n{e}")
                self.cb_autologin.blockSignals(True)
                self.cb_autologin.setChecked(True)
                self.cb_autologin.blockSignals(False)

    def verify_current_password(self, old_p):
        try:
            child = pexpect.spawn(f'env LANG=C passwd {self.user_name}')
            idx = child.expect(['Current password:', 'New password:', pexpect.EOF], timeout=3)
            if idx == 0:
                if not old_p:
                    child.close()
                    return False
                child.sendline(old_p)
                idx2 = child.expect(['New password:', 'Authentication token manipulation error', 'incorrect password', 'Authentication failure', pexpect.EOF], timeout=3)
                child.close()
                return idx2 == 0 
            elif idx == 1:
                child.close()
                return old_p == ""
            else:
                child.close()
                return False
        except pexpect.ExceptionPexpect:
            return False

    def handle_change(self):
        old_p = self.old_pass.text()
        new_p = self.new_pass.text()
        conf_p = self.new_pass_confirm.text()

        if new_p != conf_p:
            QMessageBox.warning(self, "Chyba", "Nová hesla se neshodují!")
            return

        # Ověřujeme staré heslo jen tehdy, když si ho měníme sami sobě
        if not self.is_admin_reset:
            if not self.verify_current_password(old_p):
                QMessageBox.critical(self, "Chyba", "Stávající heslo je nesprávné.")
                return

        if not new_p:
            reply = QMessageBox.question(self, 'Varování', 
                "Opravdu chcete ZRUŠIT heslo? Počítač bude nezabezpečený.",
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
            if reply == QMessageBox.Yes:
                try:
                    subprocess.run(['pkexec', 'passwd', '-d', self.user_name], check=True)
                    QMessageBox.information(self, "Hotovo", "Heslo smazáno.")
                except:
                    QMessageBox.critical(self, "Chyba", "Nepodařilo se smazat heslo.")
            return
            
        try:
            b64_pass = base64.b64encode(f"{self.user_name}:{new_p}".encode()).decode()
            cmd = f"echo '{b64_pass}' | base64 -d | /usr/sbin/chpasswd && gpasswd -d {self.user_name} nopasswdlogin 2>/dev/null || true"
            process = subprocess.run(['pkexec', 'bash', '-c', cmd], capture_output=True, text=True)
            
            if process.returncode == 0:
                if self.cb_autologin and self.cb_autologin.isChecked():
                    QMessageBox.information(self, "Úspěch", "Heslo nastaveno!\n\nPOZOR: Máš zaškrtnuté Automatické přihlášení. LightDM se tě proto na heslo nezeptá ani po odhlášení. Pro vyžadování hesla jej musíš odškrtnout.")
                else:
                    QMessageBox.information(self, "Úspěch", "Nové heslo bylo úspěšně nastaveno.")
            else:
                QMessageBox.warning(self, "Chyba", f"Systém odmítl heslo nastavit.\n{process.stderr}")
        except Exception as e:
            QMessageBox.critical(self, "Chyba", f"Kritická chyba: {str(e)}")

if __name__ == '__main__':
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    window = PasswordChanger()
    window.show()
    sys.exit(app.exec_())