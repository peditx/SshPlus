#!/bin/bash

CONFIG_FILE="/etc/sshplus.conf"
SERVICE_FILE="/etc/init.d/sshplus"
BINARY_FILE="/usr/bin/sshplus"

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Install dependencies
echo "Updating package lists and installing required packages..."
opkg update && opkg install sshpass whiptail

# Get SSH configuration from user
echo "Enter SSH Host:"
read -r SSH_HOST
echo "Enter SSH Username:"
read -r SSH_USER
echo "Enter SSH Password:"
read -r -s SSH_PASS
echo "Enter SSH Port (default: 22):"
read -r SSH_PORT
SSH_PORT=${SSH_PORT:-22}

# Save configuration
cat <<EOF > "$CONFIG_FILE"
SSH_HOST="$SSH_HOST"
SSH_USER="$SSH_USER"
SSH_PASS="$SSH_PASS"
SSH_PORT="$SSH_PORT"
EOF

echo "Configuration saved to $CONFIG_FILE"

# Create service to start SSH SOCKS proxy on boot
cat <<'EOF' > "$SERVICE_FILE"
#!/bin/sh /etc/rc.common
START=99
STOP=1

start() {
    source /etc/sshplus.conf
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -N -D 8089 "$SSH_USER@$SSH_HOST" -p "$SSH_PORT" &
}

stop() {
    pkill -f "sshpass -p"
}
EOF

chmod +x "$SERVICE_FILE"
/etc/init.d/sshplus enable
/etc/init.d/sshplus start

# Check if Passwall or Passwall2 is installed and configure
if service passwall2 status > /dev/null 2>&1; then
    # Passwall2 is installed
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
    echo "Passwall2 configuration updated successfully."
elif service passwall status > /dev/null 2>&1; then
    # Passwall is installed
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
    echo "Passwall configuration updated successfully."
else
    echo "Neither Passwall nor Passwall2 is installed. Skipping configuration."
fi

# Create the SSHPlus management script
cat <<'EOF' > "$BINARY_FILE"
#!/bin/bash

CONFIG_FILE="/etc/sshplus.conf"
SERVICE_FILE="/etc/init.d/sshplus"

menu() {
    OPTION=$(whiptail --title "PeDitX OS SshPlus on passwall" --menu "Choose an option" 15 50 3 \
        "1" "Edit SSH Config" \
        "2" "Start SSH Service" \
        "3" "Stop SSH Service" 3>&1 1>&2 2>&3)

    case $OPTION in
        1)
            edit_config
            ;;
        2)
            start_service
            ;;
        3)
            stop_service
            ;;
    esac
}

edit_config() {
    SSH_HOST=$(whiptail --title "PeDitX OS SshPlus on passwall" --inputbox "Enter SSH Host:" 10 50 3>&1 1>&2 2>&3)
    SSH_USER=$(whiptail --title "PeDitX OS SshPlus on passwall" --inputbox "Enter SSH Username:" 10 50 3>&1 1>&2 2>&3)
    SSH_PASS=$(whiptail --title "PeDitX OS SshPlus on passwall" --passwordbox "Enter SSH Password:" 10 50 3>&1 1>&2 2>&3)
    SSH_PORT=$(whiptail --title "PeDitX OS SshPlus on passwall" --inputbox "Enter SSH Port (default: 22):" 10 50 3>&1 1>&2 2>&3)

    [ -z "$SSH_PORT" ] && SSH_PORT="22"

    cat <<EOF > "$CONFIG_FILE"
SSH_HOST="$SSH_HOST"
SSH_USER="$SSH_USER"
SSH_PASS="$SSH_PASS"
SSH_PORT="$SSH_PORT"
EOF

    whiptail --title "PeDitX OS SshPlus on passwall" --msgbox "Configuration updated successfully!" 10 40
}

start_service() {
    /etc/init.d/sshplus start
    whiptail --title "PeDitX OS SshPlus on passwall" --msgbox "SSH Service started successfully!" 10 40
}

stop_service() {
    /etc/init.d/sshplus stop
    whiptail --title "PeDitX OS SshPlus on passwall" --msgbox "SSH Service stopped successfully!" 10 40
}

menu
EOF

chmod +x "$BINARY_FILE"

echo "Installation complete! Run 'sshplus' to manage your SSH proxy."
