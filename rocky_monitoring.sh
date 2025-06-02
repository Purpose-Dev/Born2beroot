#!/bin/bash

# ARCHITECTURE
arch=$(uname -a)

# CPU INFO
cpuf=$(lscpu | grep "Socket(s):" | awk '{print $2}')
cpuv=$(grep -c ^processor /proc/cpuinfo)

# RAM
ram_total=$(free -m | awk '/^Mem:/ {print $2}')
ram_use=$(free -m | awk '/^Mem:/ {print $3}')
ram_percent=$(awk "BEGIN {printf \"%.2f\", ($ram_use/$ram_total)*100}")

# DISK
disk_total=$(df -BM --total | awk '/^total/ {printf "%.1fGb", $2/1024}')
disk_use=$(df -BM --total | awk '/^total/ {print $3}')
disk_percent=$(df -BM --total | awk '/^total/ {printf "%d", $3*100/$2}')

# CPU LOAD
cpu_idle=$(vmstat 1 2 | tail -1 | awk '{print $15}')
cpu_load=$(awk "BEGIN {printf \"%.1f\", 100 - $cpu_idle}")

# LAST BOOT
lb=$(who -b | awk '{print $3 " " $4}')

# LVM USE
lvmu=$(lsblk | grep -q "lvm" && echo "yes" || echo "no")

# TCP CONNECTIONS
tcpc=$(ss -ta | grep ESTAB | wc -l)

# USER LOGGED
ulog=$(who | wc -l)

# NETWORK
ip=$(hostname -I | awk '{print $1}')
mac=$(ip link show | awk '/ether/ {print $2}' | head -n 1)

# SUDO COMMANDS
cmnd=$(journalctl _COMM=sudo | grep -c COMMAND)

# DISPLAY MESSAGE
wall <<EOF
	Architecture: $arch
	CPU physical: $cpuf
	vCPU: $cpuv
	Memory Usage: $ram_use/${ram_total}MB (${ram_percent}%)
	Disk Usage: $disk_use/${disk_total} (${disk_percent}%)
	CPU load: $cpu_load%
	Last boot: $lb
	LVM use: $lvmu
	Connections TCP: $tcpc ESTABLISHED
	User log: $ulog
	Network: IP $ip ($mac)
	Sudo: $cmnd cmd
EOF
