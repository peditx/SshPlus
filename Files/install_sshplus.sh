#!/bin/bash

# Colors
GREEN="\e[32m"
RED="\e[31m"
NC="\e[0m"

# Install necessary packages
opkg update && opkg install sshpass whiptail bash

# Prompt for SSH credentials
HOST=$(whiptail --inputbox "Enter SSH Host:" 8 40 --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)
USER=$(whiptail --inputbox "Enter SSH Username:" 8 40 --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)
PASS=$(whiptail --passwordbox "Enter SSH Password:" 8 40 --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)
PORT=$(whiptail --inputbox "Enter SSH Port:" 8 40 "22" --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)

# Save SSH credentials
CONFIG_FILE="/etc/sshplus.conf"
echo -e "HOST=${HOST}\nUSER=${USER}\nPASS=${PASS}\nPORT=${PORT}" > "$CONFIG_FILE"

# Create SSH service script
cat > /etc/init.d/sshplus << EOF
#!/bin/sh /etc/rc.common
# Start and stop commands for sshplus

START=99
STOP=10

start() {
    . "$CONFIG_FILE"
    nohup sshpass -p "\$PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -D 8089 -N -p "\$PORT" "\$USER@\$HOST" &
}

stop() {
    # Check if sshpass is running before trying to kill it
    if pgrep sshpass > /dev/null; then
        killall sshpass
    else
        echo -e "${RED}No sshpass process running to stop.${NC}"
    fi
}
EOF

# Set permissions and enable service
chmod +x /etc/init.d/sshplus
/etc/init.d/sshplus enable
/etc/init.d/sshplus start

# Configure Passwall or Passwall2
if service passwall2 status > /dev/null 2>&1; then
    uci set passwall2.SshPlus=nodes
    uci set passwall2.SshPlus.remarks='ssh-plus'
    uci set passwall2.SshPlus.type='Xray'
    uci set passwall2.SshPlus.protocol='socks'
    uci set passwall2.SshPlus.server='127.0.0.1'
    uci set passwall2.SshPlus.port='8089'
    uci set passwall2.SshPlus.address='127.0.0.1'
    uci set passwall2.SshPlus.tls='0'
    uci set passwall2.SshPlus.transport='tcp'
    uci set passwall2.SshPlus.tcp_guise='none'
    uci set passwall2.SshPlus.tcpMptcp='0'
    uci set passwall2.SshPlus.tcpNoDelay='0'
    uci commit passwall2
    echo -e "${GREEN}Passwall2 configuration updated successfully.${NC}"
elif service passwall status > /dev/null 2>&1; then
    uci set passwall.SshPlus=nodes
    uci set passwall.SshPlus.remarks='Ssh-Plus'
    uci set passwall.SshPlus.type='Xray'
    uci set passwall.SshPlus.protocol='socks'
    uci set passwall.SshPlus.server='127.0.0.1'
    uci set passwall.SshPlus.port='8089'
    uci set passwall.SshPlus.address='127.0.0.1'
    uci set passwall.SshPlus.tls='0'
    uci set passwall.SshPlus.transport='tcp'
    uci set passwall.SshPlus.tcp_guise='none'
    uci set passwall.SshPlus.tcpMptcp='0'
    uci set passwall.SshPlus.tcpNoDelay='0'
    uci commit passwall
    echo -e "${GREEN}Passwall configuration updated successfully.${NC}"
else
    echo -e "${RED}Neither Passwall nor Passwall2 is installed. Skipping configuration.${NC}"
fi

# Create SSHPlus management script
cat > /usr/bin/sshplus << 'EOF'
#!/bin/bash

CONFIG_FILE="/etc/sshplus.conf"

show_menu() {
    whiptail --title "PeDitX OS SshPlus on passwall" --menu "Choose an option" 15 50 3 \
    "1" "Edit SSH Config" \
    "2" "Start SSH Service" \
    "3" "Stop SSH Service" 3>&1 1>&2 2>&3
}

edit_config() {
    HOST=$(whiptail --inputbox "Enter SSH Host:" 8 40 "$(grep HOST= "$CONFIG_FILE" | cut -d'=' -f2)" --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)
    USER=$(whiptail --inputbox "Enter SSH Username:" 8 40 "$(grep USER= "$CONFIG_FILE" | cut -d'=' -f2)" --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)
    PASS=$(whiptail --passwordbox "Enter SSH Password:" 8 40 --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)
    PORT=$(whiptail --inputbox "Enter SSH Port:" 8 40 "$(grep PORT= "$CONFIG_FILE" | cut -d'=' -f2)" --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)

    echo -e "HOST=${HOST}\nUSER=${USER}\nPASS=${PASS}\nPORT=${PORT}" > "$CONFIG_FILE"
}

start_ssh_service() {
    service sshplus start
}

stop_ssh_service() {
    service sshplus stop
}

while true; do
    CHOICE=$(show_menu)
    case $CHOICE in
        1) edit_config ;;
        2) start_ssh_service ;;
        3) stop_ssh_service ;;
        *) exit ;;
    esac
done
EOF

# Set permissions
chmod +x /usr/bin/sshplus

echo -e "${GREEN}Installation completed. Run 'sshplus' to manage the SSH service.${NC}"
