#!/usr/bin/env python3
import os
import sys
import subprocess
import time
import hashlib

# Automatická detekce správné složky plochy (česká i anglická verze)
DESKTOP_DIR = os.path.expanduser("~/Desktop")
if not os.path.exists(DESKTOP_DIR):
    DESKTOP_DIR = os.path.expanduser("~/Plocha")

if not os.path.exists(DESKTOP_DIR):
    print("Chyba: Složka Plocha/Desktop nebyla nalezena!", file=sys.stderr)
    sys.exit(1)

def get_file_sha256(filepath):
    """Spočítá SHA-256 hash souboru, který XFCE vyžaduje jako kontrolní součet."""
    hasher = hashlib.sha256()
    try:
        with open(filepath, 'rb') as f:
            while chunk := f.read(8192):
                hasher.update(chunk)
        return hasher.hexdigest()
    except Exception:
        return None

def fix_desktop_file(filepath):
    """Přidá souboru spustitelná práva a vygeneruje správný XFCE kontrolní součet."""
    if not filepath.endswith(".desktop"):
        return False
        
    try:
        # 1. Spočítáme reálný SHA-256 otisk souboru
        file_hash = get_file_sha256(filepath)
        if not file_hash:
            return False

        # 2. Kontrola, zda už soubor náhodou nemá shodný hash zapsaný (šetříme procesy)
        res = subprocess.run(
            ["gio", "info", "-a", "metadata::xfce-exe-checksum", filepath],
            capture_output=True, text=True
        )
        if file_hash in res.stdout:
            return False 

        # 3. Klasické Linuxové právo na spuštění (rwxr-xr-x)
        os.chmod(filepath, 0o755)
        
        # 4. Zápis reálného SHA-256 hashe do metadat (simulace kliknutí na "Označit jako bezpečné")
        subprocess.run([
            "gio", "set", "-t", "string", filepath, 
            "metadata::xfce-exe-checksum", file_hash
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        print(f"Úspěšně schváleno (vygenerován hash): {os.path.basename(filepath)}")
        return True
    except Exception as e:
        print(f"Chyba při opravě {filepath}: {e}", file=sys.stderr)
        return False

def main():
    print(f"Sleduji složku: {DESKTOP_DIR}")
    
    # Prvotní vyčištění plochy hned po startu systému
    for item in os.listdir(DESKTOP_DIR):
        fix_desktop_file(os.path.join(DESKTOP_DIR, item))

    # Uchováme si seznam souborů na ploše
    last_snapshot = set(os.listdir(DESKTOP_DIR))

    # Reálné sledování změn
    while True:
        try:
            time.sleep(0.5)
            current_snapshot = set(os.listdir(DESKTOP_DIR))
            
            # Najdeme nově přidané nebo přesunuté soubory
            new_items = current_snapshot - last_snapshot
            if new_items:
                # Malá pauza, aby Thunar stihl soubor na plochu kompletně zapsat před výpočtem hashe
                time.sleep(0.3)
                for item in new_items:
                    full_path = os.path.join(DESKTOP_DIR, item)
                    if os.path.exists(full_path):
                        fix_desktop_file(full_path)
            
            last_snapshot = current_snapshot
            
        except KeyboardInterrupt:
            print("\nUkončuji sledování.")
            sys.exit(0)
        except Exception as e:
            time.sleep(2)

if __name__ == "__main__":
    main()
