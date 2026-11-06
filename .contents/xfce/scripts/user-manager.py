#!/usr/bin/env python3
import sys
import os
import subprocess
import pwd
import grp
from PyQt5.QtWidgets import (QApplication, QWidget, QVBoxLayout, QHBoxLayout, 
                             QLineEdit, QPushButton, QMessageBox, QListWidget, 
                             QListWidgetItem, QLabel, QInputDialog, QDialog, QFrame)
from PyQt5.QtCore import Qt, QSize, QThread, pyqtSignal
from PyQt5.QtGui import QFont

# --- VLÁKNO PRO SYSTÉMOVÉ PŘÍKAZY S PRÁVY ROOT ---
class SysAdminWorker(QThread):
    finished = pyqtSignal(int, str, str)

    def __init__(self, cmd, action_name):
        super().__init__()
        self.cmd = cmd
        self.action_name = action_name

    def run(self):
        try:
            result = subprocess.run(['pkexec', 'bash', '-c', self.cmd], capture_output=True, text=True)
            self.finished.emit(result.returncode, result.stderr, self.action_name)
        except Exception as e:
            self.finished.emit(1, str(e), self.action_name)


# --- DIALOG PRO SPRÁVU SKUPIN ---
class GroupManagerDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Nastavení skupin")
        self.setFixedSize(380, 420)
        self.worker = None
        self.initUI()
        self.load_groups()

    def initUI(self):
        layout = QHBoxLayout()
        self.setStyleSheet(self.parent().styleSheet())
        
        self.group_list = QListWidget()
        layout.addWidget(self.group_list)
        
        btn_layout = QVBoxLayout()
        
        self.btn_add = QPushButton('+ Přidat')
        self.btn_add.setCursor(Qt.PointingHandCursor)
        self.btn_add.clicked.connect(self.add_group)
        
        self.btn_del = QPushButton('- Smazat')
        self.btn_del.setCursor(Qt.PointingHandCursor)
        self.btn_del.clicked.connect(self.del_group)
        
        btn_layout.addWidget(self.btn_add)
        btn_layout.addWidget(self.btn_del)
        btn_layout.addStretch()
        
        layout.addLayout(btn_layout)
        self.setLayout(layout)

    def load_groups(self):
        self.group_list.clear()
        all_groups = sorted([g.gr_name for g in grp.getgrall()])
        self.group_list.addItems(all_groups)

    def add_group(self):
        name, ok = QInputDialog.getText(self, "Nová skupina", "Zadejte název nové skupiny:")
        if ok and name.strip():
            self.run_command(f"groupadd {name.strip()}", "add_group")

    def del_group(self):
        curr = self.group_list.currentItem()
        if not curr: return
        g_name = curr.text()
        reply = QMessageBox.question(self, 'Potvrzení', f"Opravdu smazat skupinu {g_name}?", QMessageBox.Yes | QMessageBox.No)
        if reply == QMessageBox.Yes:
            self.run_command(f"groupdel {g_name}", "del_group")

    def run_command(self, cmd, action):
        self.worker = SysAdminWorker(cmd, action)
        self.worker.finished.connect(self.on_command_finished)
        self.worker.start()

    def on_command_finished(self, code, err, action):
        if code == 0:
            self.load_groups()
        else:
            QMessageBox.critical(self, "Chyba", f"Akce selhala:\n{err}")


# --- HLAVNÍ OKNO - SPRÁVCE UŽIVATELŮ ---
class UserManagerApp(QWidget):
    def __init__(self):
        super().__init__()
        self.worker = None
        self.current_user = None
        self.initUI()
        self.load_users()

    def initUI(self):
        self.setWindowTitle('Nastavení uživatelů')
        self.setFixedSize(720, 500) # Zvětšeno pro lepší přehlednost
        
        self.setStyleSheet("""
            QWidget { background-color: #f5f5f5; font-family: sans-serif; }
            QLabel { color: #333; font-size: 11pt; }
            QListWidget { background-color: white; border: 1px solid #ccc; border-radius: 5px; outline: 0; font-size: 11pt; }
            QListWidget::item { padding: 10px; color: #222; }
            QListWidget::item:hover { background-color: #e3f2fd; }
            QListWidget::item:selected { background-color: #2a7fca; color: white; border-radius: 3px; }
            QPushButton { background-color: #e0e0e0; color: #222; padding: 8px 15px; border: 1px solid #ccc; border-radius: 5px; font-size: 10pt; min-width: 120px; }
            QPushButton:hover { background-color: #d5d5d5; }
            QPushButton:disabled { background-color: #e0e0e0; color: #9e9e9e; border: 1px solid #d5d5d5; }
        """)

        main_layout = QHBoxLayout()
        main_layout.setContentsMargins(20, 20, 20, 20)
        main_layout.setSpacing(20)

        # LEVÝ PANEL - Seznam a tlačítka
        left_layout = QVBoxLayout()
        self.user_list = QListWidget()
        self.user_list.itemSelectionChanged.connect(self.on_user_selected)
        left_layout.addWidget(self.user_list)

        btn_row_1 = QHBoxLayout()
        self.btn_add = QPushButton('+ Přidat')
        self.btn_add.setCursor(Qt.PointingHandCursor)
        self.btn_add.clicked.connect(self.add_user)
        self.btn_del = QPushButton('- Smazat')
        self.btn_del.setCursor(Qt.PointingHandCursor)
        self.btn_del.clicked.connect(self.delete_user)
        btn_row_1.addWidget(self.btn_add)
        btn_row_1.addWidget(self.btn_del)
        left_layout.addLayout(btn_row_1)

        self.btn_groups = QPushButton('Spravovat skupiny')
        self.btn_groups.setCursor(Qt.PointingHandCursor)
        self.btn_groups.clicked.connect(self.open_groups)
        left_layout.addWidget(self.btn_groups)

        main_layout.addLayout(left_layout, 1)

        # PRAVÝ PANEL - Detaily pod sebou (čistý vertikální layout)
        self.right_panel = QFrame()
        right_layout = QVBoxLayout()
        right_layout.setSpacing(15)
        self.right_panel.setLayout(right_layout)
        
        # 1. Sekce Jméno
        name_box = QVBoxLayout()
        self.lbl_realname = QLabel("Vyberte uživatele")
        self.lbl_realname.setFont(QFont("sans-serif", 14, QFont.Bold))
        self.lbl_login = QLabel("")
        self.lbl_login.setStyleSheet("color: #666;")
        name_box.addWidget(self.lbl_realname)
        name_box.addWidget(self.lbl_login)
        right_layout.addLayout(name_box)
        
        self.btn_edit_name = QPushButton("Přejmenovat uživatele")
        self.btn_edit_name.setCursor(Qt.PointingHandCursor)
        right_layout.addWidget(self.btn_edit_name, 0, Qt.AlignLeft)
        self.btn_edit_name.clicked.connect(self.edit_real_name)
        
        # Oddělovač
        line1 = QFrame()
        line1.setFrameShape(QFrame.HLine)
        line1.setStyleSheet("color: #ddd;")
        right_layout.addWidget(line1)

        # 2. Sekce Typ účtu (Sudo)
        type_box = QVBoxLayout()
        self.lbl_type = QLabel("Typ účtu: Standardní")
        type_box.addWidget(self.lbl_type)
        right_layout.addLayout(type_box)
        
        self.btn_toggle_sudo = QPushButton("Změnit oprávnění")
        self.btn_toggle_sudo.setCursor(Qt.PointingHandCursor)
        right_layout.addWidget(self.btn_toggle_sudo, 0, Qt.AlignLeft)
        self.btn_toggle_sudo.clicked.connect(self.toggle_sudo)

        # Oddělovač
        line2 = QFrame()
        line2.setFrameShape(QFrame.HLine)
        line2.setStyleSheet("color: #ddd;")
        right_layout.addWidget(line2)

        # 3. Sekce Heslo
        pass_box = QVBoxLayout()
        lbl_pass_title = QLabel("Zabezpečení přihlášení a relace")
        pass_box.addWidget(lbl_pass_title)
        right_layout.addLayout(pass_box)
        
        self.btn_change_pass = QPushButton("Změnit heslo / Autologin")
        self.btn_change_pass.setCursor(Qt.PointingHandCursor)
        right_layout.addWidget(self.btn_change_pass, 0, Qt.AlignLeft)
        self.btn_change_pass.clicked.connect(self.launch_password_script)

        right_layout.addStretch()
        main_layout.addWidget(self.right_panel, 2)
        
        self.setLayout(main_layout)
        self.right_panel.setDisabled(True)

    def load_users(self):
        self.user_list.clear()
        users = [u for u in pwd.getpwall() if 1000 <= u.pw_uid < 65000]
        for u in sorted(users, key=lambda x: x.pw_name):
            item = QListWidgetItem(f"{u.pw_gecos.split(',')[0] or u.pw_name}\n({u.pw_name})")
            item.setData(Qt.UserRole, u.pw_name)
            self.user_list.addItem(item)
            
        if self.user_list.count() > 0:
            self.user_list.setCurrentRow(0)

    def on_user_selected(self):
        curr = self.user_list.currentItem()
        if not curr:
            self.right_panel.setDisabled(True)
            return
            
        self.right_panel.setDisabled(False)
        self.current_user = curr.data(Qt.UserRole)
        
        try:
            user_info = pwd.getpwnam(self.current_user)
            real_name = user_info.pw_gecos.split(',')[0] or self.current_user
            self.lbl_realname.setText(real_name)
            self.lbl_login.setText(f"Login: {self.current_user}  |  Domovská složka: {user_info.pw_dir}")
            
            is_admin = self.current_user in grp.getgrnam('sudo').gr_mem
            self.lbl_type.setText(f"Typ účtu: <b>{'Správce (Sudo)' if is_admin else 'Standardní'}</b>")
            self.btn_toggle_sudo.setText("Odebrat admin práva" if is_admin else "Přidat admin práva")
        except:
            pass

    def add_user(self):
        login, ok1 = QInputDialog.getText(self, "Nový uživatel", "Zadejte přihlašovací jméno (login, např. novak):")
        if not ok1 or not login.strip(): return
        
        real_name, ok2 = QInputDialog.getText(self, "Nový uživatel", "Zadejte celé jméno (např. Jan Novák):")
        if not ok2: return
        
        cmd = f"useradd -m -s /bin/bash -c '{real_name.strip()}' {login.strip()}"
        self.run_command(cmd, "add_user")

    def delete_user(self):
        if not self.current_user: return
        if self.current_user == pwd.getpwuid(os.getuid()).pw_name:
            QMessageBox.warning(self, "Chyba", "Nemůžete smazat uživatele, pod kterým jste právě přihlášeni.")
            return
            
        reply = QMessageBox.question(self, 'Varování', 
            f"Opravdu chcete trvale smazat uživatele <b>{self.current_user}</b>?<br><br>Tato akce nekompromisně smaže i celou jeho domovskou složku (/home/{self.current_user}).",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
            
        if reply == QMessageBox.Yes:
            self.run_command(f"userdel -r {self.current_user}", "del_user")

    def edit_real_name(self):
        if not self.current_user: return
        curr_name = pwd.getpwnam(self.current_user).pw_gecos.split(',')[0]
        new_name, ok = QInputDialog.getText(self, "Přejmenovat", "Nové zobrazované jméno:", text=curr_name)
        if ok and new_name.strip():
            self.run_command(f"usermod -c '{new_name.strip()}' {self.current_user}", "edit_name")

    def toggle_sudo(self):
        if not self.current_user: return
        is_admin = self.current_user in grp.getgrnam('sudo').gr_mem
        if is_admin:
            self.run_command(f"gpasswd -d {self.current_user} sudo", "toggle_sudo")
        else:
            self.run_command(f"gpasswd -a {self.current_user} sudo", "toggle_sudo")

    def launch_password_script(self):
        if not self.current_user: return
        
        script_path = os.path.expanduser("~/.local/share/bin/change-password.py")
        fallback_path = os.path.expanduser("~/.local/bin/change-password.py")
        target_path = script_path if os.path.exists(script_path) else fallback_path
        
        if not os.path.exists(target_path):
            QMessageBox.warning(self, "Chyba", f"Skript pro změnu hesla nebyl nalezen na cestě:\n{target_path}")
            return
            
        env = os.environ.copy()
        env["SUDO_USER"] = self.current_user
        
        try:
            subprocess.Popen(["python3", target_path], env=env)
        except Exception as e:
            QMessageBox.critical(self, "Chyba", f"Nepodařilo se spustit modul hesla:\n{e}")

    def open_groups(self):
        dlg = GroupManagerDialog(self)
        dlg.exec_()

    def run_command(self, cmd, action):
        self.setEnabled(False)
        self.worker = SysAdminWorker(cmd, action)
        self.worker.finished.connect(self.on_command_finished)
        self.worker.start()

    def on_command_finished(self, code, err, action):
        self.setEnabled(True)
        if code == 0:
            if action in ["add_user", "del_user", "edit_name"]:
                self.load_users()
            elif action == "toggle_sudo":
                self.on_user_selected()
        else:
            QMessageBox.critical(self, "Chyba systému", f"Příkaz selhal:\n\n{err}")


if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = UserManagerApp()
    window.show()
    sys.exit(app.exec_())
