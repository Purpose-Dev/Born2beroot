#******************************************************************************#
#                                                                              #
#                                                         :::      ::::::::    #
#    rocky_install.sh                                   :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: rel-qoqu <rel-qoqu@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2025/05/20 03:12:16 by rel-qoqu          #+#    #+#              #
#    Updated: 2025/05/20 03:55:21 by rel-qoqu         ###   ########.fr        #
#                                                                              #
#******************************************************************************#

#!/bin/bash

set -e

NEW_USER="rel-qoqu42"
SSH_PORT=4242

sudo dnf install policycoreutils-python-utils -y

echo "[*] Installation et configuration de firewalld..."
dnf install firewalld -y
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=${SSH_PORT}/tcp
firewall-cmd --reload

echo "[*] Configuration du SSH (port $SSH_PORT, root interdit)..."
sed -i "s/^#Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^#PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
if ! semanage port -l | grep -q "$SSH_PORT"; then
  semanage port -a -t ssh_port_t -p tcp $SSH_PORT
fi
systemctl restart sshd

echo "[*] Politique de mot de passe (pwquality)..."
cp /etc/security/pwquality.conf /etc/security/pwquality.conf.bak
cat <<EOF > /etc/security/pwquality.conf
minlen = 10
dcredit = 1
ucredit = 1
lcredit = 1
maxrepeat = 3
reject_username = 1
difok = 7
EOF

echo "[*] Sudo log..."
echo 'Defaults logfile="/var/log/sudo.log"' >> /etc/sudoers

echo "[*] Création du groupe user42 et ajout de $NEW_USER..."
groupadd -f user42
usermod -aG user42 $NEW_USER

echo "[*] Expiration mot de passe..."
chage -M 30 -m 2 -W 7 "$NEW_USER"

echo "[*] Création du script de monitoring..."
cat <<'EOF' > /root/monitoring.sh
#!/bin/bash

arch=$(uname -a)
cpuf=$(lscpu | grep "Socket(s):" | awk '{print $2}')
cpuv=$(grep -c ^processor /proc/cpuinfo)
ram_total=$(free -m | awk '/^Mem:/ {print $2}')
ram_use=$(free -m | awk '/^Mem:/ {print $3}')
ram_percent=$(awk "BEGIN {printf \"%.2f\", ($ram_use/$ram_total)*100}")
disk_total=$(df -BM --total | awk '/^total/ {printf "%.1fGb", $2/1024}')
disk_use=$(df -BM --total | awk '/^total/ {print $3}')
disk_percent=$(df -BM --total | awk '/^total/ {printf "%d", $3*100/$2}')
cpu_idle=$(vmstat 1 2 | tail -1 | awk '{print $15}')
cpu_load=$(awk "BEGIN {printf \"%.1f\", 100 - $cpu_idle}")
lb=$(who -b | awk '{print $3 " " $4}')
lvmu=$(lsblk | grep -q "lvm" && echo "yes" || echo "no")
tcpc=$(ss -ta | grep ESTAB | wc -l)
ulog=$(who | wc -l)
ip=$(hostname -I | awk '{print $1}')
mac=$(ip link show | awk '/ether/ {print $2}' | head -n 1)
cmnd=$(journalctl _COMM=sudo | grep -c COMMAND)

wall <<MSG
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
MSG
EOF

chmod +x /root/monitoring.sh

echo "[*] Ajout de la tâche cron pour le monitoring toutes les 10 minutes..."
(crontab -l 2>/dev/null | grep -q '/root/monitoring.sh') || \
(crontab -l 2>/dev/null; echo "*/10 * * * * /root/monitoring.sh") | crontab -

echo "[*] Configuration du monitoring terminée."
echo "[*] Installation de fail2ban et auditd..."
dnf install epel-release -y
dnf makecache
dnf update -y
dnf install fail2ban audit -y
systemctl enable --now auditd
systemctl enable --now fail2ban

echo "[*] Configuration de fail2ban..."
cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/secure
maxretry = 3
bantime = 3600
findtime = 600
action = iptables[name=sshd, port=$SSH_PORT, protocol=tcp]
EOF
systemctl restart fail2ban

echo "[*] Configuration de l'auditd..."
cat <<EOF > /etc/audit/rules.d/audit.rules
# Audit rules
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes
-w /etc/gshadow -p wa -k gshadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/ssh/sshd_config -p wa -k sshd_config_changes
-w /var/log/secure -p wa -k secure_log_changes
-w /var/log/audit/audit.log -p wa -k audit_log_changes
-w /var/log/messages -p wa -k messages_log_changes
-w /var/log/cron -p wa -k cron_log_changes
-w /var/log/maillog -p wa -k maillog_changes
-w /var/log/httpd -p wa -k httpd_log_changes
-w /var/log/secure -p wa -k secure_log_changes
-w /var/log/boot.log -p wa -k boot_log_changes
-w /var/log/lastlog -p wa -k lastlog_changes
-w /var/log/utmp -p wa -k utmp_changes
-w /var/log/wtmp -p wa -k wtmp_changes
-w /var/log/btmp -p wa -k btmp_changes
EOF
systemctl restart auditd

echo "[*] Installation de lighttpd, MariaDB et PHP..."
dnf install lighttpd mariadb-server php php-mysqlnd php-fpm php-gd php-xml php-mbstring -y

echo "[*] Activation et démarrage des services..."
systemctl enable --now lighttpd
systemctl enable --now mariadb
systemctl enable --now php-fpm

echo "[*] Sécurisation de MariaDB (mot de passe root vide, à changer ensuite)..."
mysql_secure_installation <<EOF

y
Password42
Password42
y
y
y
y
EOF

echo "[*] Création de la base de données WordPress..."
mysql -u root -pPassword42 <<EOF
CREATE DATABASE wordpress;
CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'WpPass42!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "[*] Téléchargement et installation de WordPress..."
cd /var/www
curl -O https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* /var/www/lighttpd/
chown -R lighttpd:lighttpd /var/www/lighttpd/
rm -rf wordpress latest.tar.gz

echo "[*] Configuration de lighttpd pour PHP et WordPress..."
cat <<EOF > /etc/lighttpd/conf.d/wordpress.conf
server.document-root = "/var/www/lighttpd"
index-file.names = ( "index.php", "index.html" )
include "conf.d/fastcgi.conf"
EOF

sed -i '/"mod_fastcgi"/s/#//' /etc/lighttpd/modules.conf
sed -i '/"mod_rewrite"/s/#//' /etc/lighttpd/modules.conf

systemctl restart lighttpd
systemctl restart php-fpm

firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

echo "[*] WordPress installé sur http://<IP_VM>:80"

echo "[*] Installation de Cockpit (interface web d'administration)..."
dnf install cockpit -y
systemctl enable --now cockpit.socket
firewall-cmd --permanent --add-service=cockpit
firewall-cmd --reload

echo "[*] Cockpit disponible sur https://<IP_VM>:9090"

echo "[*] Setup terminé !"
echo "[*] Redémarrage suggéré : reboot"
