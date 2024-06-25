#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1"
}

# Function to generate a random string
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Function to generate an IPv6 address
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Function to install 3proxy
install_3proxy() {
    log "Installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.8.6.tar.gz"
    wget -qO- $URL | tar -zxvf- || { log "3proxy download or extraction failed"; exit 1; }
    cd 3proxy-0.8.6 || { log "3proxy directory not found"; exit 1; }
    make -f Makefile.Linux || { log "Make failed"; exit 1; }
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    cd $WORKDIR
}

# Function to generate 3proxy configuration
gen_3proxy() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

# Function to generate proxy file for user
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Function to upload proxy file to file.io
upload_proxy() {
    RESPONSE=$(curl -F "file=@proxy.txt" https://file.io)
    log "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    log "Download link: ${RESPONSE}"
}

# Function to generate data
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read -r port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

# Function to generate iptables script
gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

# Function to generate ifconfig script
gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

log "Installing required packages"
yum -y install gcc net-tools bsdtar zip curl || { log "Failed to install dependencies"; exit 1; }

# Variables
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"

# Ensure the working directory exists
mkdir -p $WORKDIR || { log "Failed to create working directory"; exit 1; }
cd $WORKDIR || { log "Failed to navigate to working directory"; exit 1; }

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

log "Internal IP = ${IP4}. External sub for IP6 = ${IP6}"

log "How many proxies do you want to create? Example: 500"
read -r COUNT

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT))

gen_data > "$WORKDIR/data.txt"
gen_iptables > "$WORKDIR/boot_iptables.sh"
gen_ifconfig > "$WORKDIR/boot_ifconfig.sh"
chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local

install_3proxy

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg

cat >> /etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

bash /etc/rc.local

gen_proxy_file_for_user

upload_proxy
