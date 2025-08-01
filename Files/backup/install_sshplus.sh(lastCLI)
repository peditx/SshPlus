#!/bin/bash

# Colors
GREEN="\e[32m"
RED="\e[31m"
NC="\e[0m"

# Install necessary packages
opkg update
opkg remove dropbear
opkg install openssh-server openssh-client sshpass whiptail bash screen

sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
/etc/init.d/sshd restart

# Prompt for SSH credentials
HOST=$(whiptail --inputbox "Enter SSH Host:" 8 40 --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)
USER=$(whiptail --inputbox "Enter SSH Username:" 8 40 --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)
PASS=$(whiptail --passwordbox "Enter SSH Password:" 8 40 --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)
PORT=$(whiptail --inputbox "Enter SSH Port (e.g. 22 or 2222):" 8 40 "22" --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)

# Validate that PORT is a number
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Invalid port number!${NC}"
    exit 1
fi

# Save SSH credentials
CONFIG_FILE="/etc/sshplus.conf"
echo -e "HOST=${HOST}\nUSER=${USER}\nPASS=${PASS}\nPORT=${PORT}" > "$CONFIG_FILE"

# Create SSH service script
cat > /etc/init.d/sshplus << EOF
#!/bin/sh /etc/rc.common
START=99
STOP=10

start() {
    . "$CONFIG_FILE"
    screen -dmS sshplus sshpass -p "\$PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -D 8089 -N -p "\$PORT" "\$USER@\$HOST"
}

stop() {
    screens=\$(screen -ls | grep "sshplus" | awk '{print \$1}' | sed 's/\\..*//')

    if [ -n "\$screens" ]; then
        for s in \$screens; do
            screen -S "\$s" -X quit
        done
        echo -e "${GREEN}All SSHPlus sessions stopped.${NC}"
    else
        echo -e "${RED}No active SSHPlus session found.${NC}"
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
    PORT=$(whiptail --inputbox "Enter SSH Port (e.g. 22 or 2222):" 8 40 "$(grep PORT= "$CONFIG_FILE" | cut -d'=' -f2)" --title "PeDitX OS SshPlus on passwall" 3>&1 1>&2 2>&3)

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

echo -e "${GREEN}Installation completed. Run 'sshplus' to manage the SSH service. Made by PeDitX https://t.me/peditx${NC}"
