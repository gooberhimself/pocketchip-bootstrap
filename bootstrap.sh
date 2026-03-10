#!/bin/sh
set -e

echo "[INIT] Starting PocketCHIP bootstrap script..."

# MUST be run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] This script must be run as root (use sudo)"
  exit 1
fi

echo "[OK] Running as root"

##### Backup sources.list #####
echo "[STEP] Backing up existing APT sources.list"
cp /etc/apt/sources.list /etc/apt/sources.list.bak || true
echo "[OK] sources.list backup complete"

##### Set sources.list #####
echo "[STEP] Writing PocketCHIP-compatible APT sources"
cat >/etc/apt/sources.list <<'EOF'
# Debian Jessie (archived)
deb [trusted=yes] http://archive.debian.org/debian jessie main contrib non-free
deb-src [trusted=yes] http://archive.debian.org/debian jessie main contrib non-free

# Debian Jessie security (archived)
deb [trusted=yes] http://archive.debian.org/debian-security jessie/updates main contrib non-free
deb-src [trusted=yes] http://archive.debian.org/debian-security jessie/updates main contrib non-free

# CHIP / PocketCHIP repositories
deb [trusted=yes] http://chip.jfpossibilities.com/chip/debian/repo jessie main
deb [trusted=yes] http://chip.jfpossibilities.com/chip/debian/pocketchip jessie main
EOF
echo "[OK] APT sources configured"

##### Fix APT #####
echo "[STEP] Applying APT compatibility fixes for Debian Jessie"

cat >/etc/apt/apt.conf.d/99jessie-archive <<EOF
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOF

cat >/etc/apt/apt.conf.d/99no-translations <<EOF
Acquire::Languages "none";
EOF

cat >/etc/apt/apt.conf.d/99force-ipv4 <<EOF
Acquire::ForceIPv4 "true";
EOF

cat >/etc/apt/apt.conf.d/99no-gpg-warnings <<EOF
APT::Get::AllowUnauthenticated "true";
EOF

echo "[OK] APT configuration fixes applied"

##### Refresh APT and setup locales #####
echo "[STEP] Refreshing APT package lists"
apt-get clean
rm -rf /var/lib/apt/lists/*
apt-get update

echo "[STEP] Installing and configuring system locale (en_US.UTF-8)"
export DEBIAN_FRONTEND=noninteractive

apt-get install -y locales
apt-get install -y kbd

sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

cat >/etc/default/locale <<EOF
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
EOF

echo "[OK] Locale generated and set"

echo "[STEP] Upgrading installed packages"
apt-get upgrade -y
echo "[OK] System packages updated"

##### Timezone (Jessie-safe) #####
echo "[STEP] Setting system timezone to America/Chicago"
echo "America/Chicago" >/etc/timezone
dpkg-reconfigure -f noninteractive tzdata
echo "[OK] Timezone configured"

##### Install personal applications #####
echo "[STEP] Installing personal applications (vim, figlet)"
apt-get install -y vim git python3
echo "[OK] Applications installed"

##### Create scripts directory #####
echo "[STEP] Creating clock script directory"
mkdir -p /home/chip/scripts/clock

echo "[STEP] Writing clock script"

cat >/home/chip/scripts/clock/bclock.py <<'EOF'
#!/usr/bin/env python3

import os
import time
import shutil
import re

# ANSI colors (PocketCHIP-safe)
BRIGHT = "\033[31m"     # bright blue
DIM    = "\033[34;2m"  # dim blue
RESET  = "\033[0m"

HEIGHT = 9

GLYPHS = {
    "0": [
        ":::::::::::",
	"::'█████:::",
	":'██.. ██::",
	"'██:::: ██:",
	" ██:::: ██:",
	" ██:::: ██:",
	". ██:: ██::",
	":. █████:::",
	"::.....::::",
    ],
    "1": [
        ":::::::::",
	":::'██:::",
	":'████:::",
	":.. ██:::",
	"::: ██:::",
	"::: ██:::",
	"::: ██:::",
	":'██████:",
	":......::",
    ],
    "2": [
        ":::::::::::",
	":'███████::",
	"'██.... ██:",
	"..::::: ██:",
	":'███████::",
	"'██::::::::",
	" ██::::::::",
	" █████████:",
	".........::",
    ],
    "3": [
        ":::::::::::",
	":'███████::",
	"'██.... ██:",
	"..::::: ██:",
	":'███████::",
	":...... ██:",
	"'██:::: ██:",
	". ███████::",
	":.......:::",
    ],
    "4": [
        ":::::::::::",
	"'██::::::::",
	" ██:::'██::",
	" ██::: ██::",
	" ██::: ██::",
	" █████████:",
	"...... ██::",
	":::::: ██::",
	"::::::..:::",
    ],
    "5": [
        "::::::::::",
	"'████████:",
	" ██.....::",
	" ██:::::::",
	" ███████::",
	"...... ██:",
	"'██::: ██:",
	". ██████::",
	":......:::",
    ],
    "6": [
        ":::::::::::",
	":'███████::",
	"'██.... ██:",
	" ██::::..::",
	" ████████::",
	" ██.... ██:",
	" ██:::: ██:",
	". ███████::",
	":.......:::",
    ],
    "7": [
        "::::::::::",
	"'████████:",
	" ██..  ██:",
	"..:: ██:::",
	"::: ██::::",
	":: ██:::::",
	":: ██:::::",
	":: ██:::::",
	"::..::::::",
    ],
    "8": [
        ":::::::::::",
	":'███████::",
	"'██.... ██:",
	" ██:::: ██:",
	": ███████::",
	"'██.... ██:",
	" ██:::: ██:",
	". ███████::",
	":.......:::",
    ],
    "9": [
	":::::::::::",
	":'███████::",
	"'██.... ██:",
	" ██:::: ██:",
	": ████████:",
	":...... ██:",
	"'██:::: ██:",
	". ███████::",
	":.......:::",
    ],
    ":": [
        "::::::",
	":'██::",
	"'████:",
	". ██::",
	":..:::",
	":'██::",
	"'████:",
	". ██::",
	":..:::",
    ]
}


def strip_ansi(s):
    return re.sub(r"\x1b\[[0-9;]*m", "", s)


def colorize(line):
    out = ""
    for ch in line:
        if ch == "█":
            out += BRIGHT + ch + RESET
        elif ch in ":.'":
            out += DIM + ch + RESET
        else:
            out += ch
    return out


def render_time(timestr):
    rows = [""] * HEIGHT
    for char in timestr:
        glyph = GLYPHS.get(char)
        if not glyph:
            continue
        for i in range(HEIGHT):
            rows[i] += glyph[i] + ""
    return rows


def center(lines):
    size = shutil.get_terminal_size((80, 24))
    width = size.columns
    height = size.lines

    pad_top = max((height - len(lines)) // 2, 0)
    output = [""] * pad_top

    for line in lines:
        visible = len(strip_ansi(line))
        pad_left = max((width - visible) // 2, 0)
        output.append(" " * pad_left + line)

    return output


def main():
    os.system("tput civis")
    last_minute = None

    try:
        while True:
            now = time.localtime()
            current_minute = time.strftime("%H:%M", now)

            # Only redraw when the minute changes
            if current_minute != last_minute:
                os.system("clear")

                art = render_time(current_minute)
                art = [colorize(line) for line in art]
                art = center(art)

                print("\n".join(art))
                last_minute = current_minute

            # Keep accurate time, but don't redraw
            time.sleep(1)

    finally:
        os.system("tput cnorm")


if __name__ == "__main__":
    main()

EOF

chown chip:chip /home/chip/scripts/clock/bclock.py 
chmod 755 /home/chip/scripts/clock/bclock.py 

echo "[OK] Clock script installed

echo "======================================"
echo "✔ PocketCHIP bootstrap complete"
echo "======================================"

