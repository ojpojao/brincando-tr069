#! /usr/bin/env bash

## author: João Paulo <joaopaulo@ion.com.br, ojpojao@gmail.com>
## Este script instala all-in-one o GenieACS com NGINX como reverse proxy e HTTPS para o módulo UI. Ele é um compilado da doc oficial https://docs.genieacs.com/en/latest/ e de outros sites como https://blog.remontti.com.br/. Não garanto que está pronto para usar em produção, mas dá pra brincar! :)
## Os módulos foram configurados para responder somente em localhost e por causa do reverse proxy as "portas-padrão", trocadas para responderem no NGINX.
## GenieACS UI: 127.0.0.1:3000
## GenieACS CWMP: 127.0.0.1:3001
## GenieACS NBI: 127.0.0.1:3002
## GenieACS UI: 127.0.0.1:3003
## O script foi testado no seguinte ambiente:
## - mongodb 5.0
## - Debian 11 (bullseye)
## - Proxmox 6.3-2, cpu=host
## - NodeJS 18.x LTS

set -xe

MONGODB_VERSION="5.0"
GENIEACS_VERSION="1.2.9"

export SSL_COUNTRY_NAME="BR"
export SSL_PROVINCE_NAME="PARAZUDO"
export SSL_LOCALITY_NAME="ANANINDEUA"
export SSL_ORGANIZATION_NAME="JOAO TRANQUEIRAS LTDA"
export SSL_ORGANIZATION_UNIT="Centro de Traquinagens(NOC)"
export SSL_COMMON_NAME="cwmp.teste.local"
export SSL_EMAIL_ADDRESS="ojpojao@teste.local"

function install_pre_reqs() {
    apt update && sudo apt install -y \
    dirmngr \
    gnupg \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    lolcat &>/dev/null # véri importante
}

function install_nodeLTS() {
    if [[ ! "$(command -v node)" ]]; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
        apt update && apt install -y nodejs
    fi
}

function install_mongodb() {
    if [[ ! "$(command -v mongo)" ]]; then
        curl -fsSL https://pgp.mongodb.com/server-$MONGODB_VERSION.pub | \
        gpg --dearmour | \
        tee /etc/apt/trusted.gpg.d/mongodb-org-$MONGODB_VERSION.gpg >/dev/null
        echo "deb [signed-by=/etc/apt/trusted.gpg.d/mongodb-org-$MONGODB_VERSION.gpg] http://repo.mongodb.org/apt/debian bullseye/mongodb-org/5.0 main" | tee /etc/apt/sources.list.d/mongodb-org-$MONGODB_VERSION.list >/dev/null
        apt update && apt install -y mongodb-org
        systemctl enable --now mongod
        systemctl status mongod --no-pager | /usr/games/lolcat
        sleep 5
        mongo --eval 'db.runCommand({ connectionStatus: 1 })' | /usr/games/lolcat
    fi
}

function install_genieacs() {
    npm install -g genieacs@$GENIEACS_VERSION
    useradd --system --no-create-home --user-group genieacs || true
    mkdir -p /opt/genieacs
    mkdir -p /opt/genieacs/ext

    cat << EOF > /opt/genieacs/genieacs-ui.env
NODE_OPTIONS="--enable-source-maps UV_THREADPOOL_SIZE=12 max_old_space_size=4096"
GENIEACS_UI_INTERFACE=127.0.0.1
GENIEACS_UI_PORT=3000
GENIEACS_UI_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-ui-access.log
GENIEACS_DEBUG_FILE=/var/log/genieacs/genieacs-debug.yaml
GENIEACS_EXT_DIR=/opt/genieacs/ext
GENIEACS_EXT_TIMEOUT=15000
GENIEACS_MAX_COMMIT_ITERATIONS=1000
GENIEACS_MAX_CONCURRENT_REQUESTS=2000
GENIEACS_MAX_DEPTH=32
EOF
    node -e "console.log(\"GENIEACS_UI_JWT_SECRET=\" + require('crypto').randomBytes(128).toString('hex'))" >> /opt/genieacs/genieacs-ui.env

    cat << EOF > /opt/genieacs/genieacs-cwmp.env
NODE_OPTIONS="--enable-source-maps UV_THREADPOOL_SIZE=12 max_old_space_size=4096"
GENIEACS_CWMP_INTERFACE=127.0.0.1
GENIEACS_CWMP_PORT=3001
GENIEACS_CWMP_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-cwmp-access.log
GENIEACS_DEBUG_FILE=/var/log/genieacs/genieacs-debug.yaml
GENIEACS_EXT_DIR=/opt/genieacs/ext
GENIEACS_EXT_TIMEOUT=15000
GENIEACS_MAX_COMMIT_ITERATIONS=1000
GENIEACS_MAX_CONCURRENT_REQUESTS=2000
GENIEACS_MAX_DEPTH=32
EOF

    cat << EOF > /opt/genieacs/genieacs-nbi.env
NODE_OPTIONS="--enable-source-maps UV_THREADPOOL_SIZE=12 max_old_space_size=4096"
GENIEACS_NBI_INTERFACE=127.0.0.1
GENIEACS_NBI_PORT=3002
GENIEACS_NBI_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-nbi-access.log
GENIEACS_DEBUG_FILE=/var/log/genieacs/genieacs-debug.yaml
GENIEACS_EXT_DIR=/opt/genieacs/ext
GENIEACS_EXT_TIMEOUT=15000
GENIEACS_MAX_COMMIT_ITERATIONS=1000
GENIEACS_MAX_CONCURRENT_REQUESTS=2000
GENIEACS_MAX_DEPTH=32
EOF

    cat << EOF > /opt/genieacs/genieacs-fs.env
NODE_OPTIONS="--enable-source-maps UV_THREADPOOL_SIZE=12 max_old_space_size=4096"
GENIEACS_FS_INTERFACE=127.0.0.1
GENIEACS_FS_PORT=3003
GENIEACS_FS_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-fs-access.log
GENIEACS_DEBUG_FILE=/var/log/genieacs/genieacs-debug.yaml
GENIEACS_EXT_DIR=/opt/genieacs/ext
GENIEACS_EXT_TIMEOUT=15000
GENIEACS_MAX_COMMIT_ITERATIONS=1000
GENIEACS_MAX_CONCURRENT_REQUESTS=2000
GENIEACS_MAX_DEPTH=32
EOF

    chown -R genieacs. /opt/genieacs
    chmod 600 /opt/genieacs/genieacs-ui.env
    chmod 600 /opt/genieacs/genieacs-cwmp.env
    chmod 600 /opt/genieacs/genieacs-nbi.env
    chmod 600 /opt/genieacs/genieacs-fs.env
    mkdir -p /var/log/genieacs
    chown genieacs. /var/log/genieacs
}

# create systemd unit files
function create_unit_files() {
    ## UI
    cat << EOF > /etc/systemd/system/genieacs-ui.service
[Unit]
Description=GenieACS UI
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs-ui.env
ExecStart=/usr/bin/genieacs-ui

[Install]
WantedBy=default.target
EOF
    ## CWMP
    cat << EOF > /etc/systemd/system/genieacs-cwmp.service
[Unit]
Description=GenieACS CWMP
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs-cwmp.env
ExecStart=/usr/bin/genieacs-cwmp

[Install]
WantedBy=default.target
EOF
    ## NBI
    cat << EOF > /etc/systemd/system/genieacs-nbi.service
[Unit]
Description=GenieACS NBI
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs-nbi.env
ExecStart=/usr/bin/genieacs-nbi

[Install]
WantedBy=default.target
EOF
    ## FS
    cat << EOF > /etc/systemd/system/genieacs-fs.service
[Unit]
Description=GenieACS FS
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs-fs.env
ExecStart=/usr/bin/genieacs-fs

[Install]
WantedBy=default.target
EOF
}

function config_log_rotation() {
    cat << EOF > /etc/logrotate.d/genieacs
/var/log/genieacs/*.log /var/log/genieacs/*.yaml {
    daily
    rotate 30
    compress
    delaycompress
    dateext
}
EOF
}

function restart_services() {
    echo "Finishing GenieACS install...."
    systemctl daemon-reload
    systemctl enable genieacs-{cwmp,fs,ui,nbi}
    sleep 2
    systemctl start genieacs-{cwmp,fs,ui,nbi}
    sleep 2
    # systemctl enable nginx
    sleep 2
    systemctl restart nginx
    sleep 2
    systemctl status nginx --no-pager | /usr/games/lolcat
    systemctl status genieacs-{cwmp,fs,ui,nbi} --no-pager | /usr/games/lolcat
}

function install_nginx() {

    apt install -y nginx
    openssl req \
    -new \
    -newkey rsa:4096 \
    -days 365 \
    -nodes \
    -x509 \
    -subj "/C=$SSL_COUNTRY_NAME/ST=$SSL_PROVINCE_NAME/L=$SSL_LOCALITY_NAME/O=$SSL_ORGANIZATION_NAME/OU=$SSL_ORGANIZATION_UNIT/CN=$SSL_COMMON_NAME" \
    -keyout /etc/ssl/private/genieacs-ui.key \
    -out /etc/ssl/certs/genieacs-ui.crt
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default
    cat << EOF > /etc/nginx/sites-available/genieacs
# redirect UI to https
server {
    listen 80;
    # listen [::]:80;
    server_name \$host;
    return 301 https://\$host\$request_uri;
}
# UI https
server {
  listen 443 ssl;
  server_name \$host;

  ssl_certificate /etc/ssl/certs/genieacs-ui.crt;
  ssl_certificate_key /etc/ssl/private/genieacs-ui.key;

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    # proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    # proxy_set_header X-Forwarded-Proto \$scheme;
    # proxy_read_timeout 3600;
    # proxy_pass_request_headers on;
  }
}
# CWMP
server {
    listen 7547;
    listen [::]:7547;
    server_name \$host;

    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        # proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        # proxy_set_header X-Forwarded-Proto \$scheme;
        # proxy_read_timeout 3600;
        # proxy_pass_request_headers on;
    }
}
# NBI
server {
    listen 7557;
    listen [::]:7557;
    server_name \$host;

    location / {
        proxy_pass http://127.0.0.1:3002;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        # proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        # proxy_set_header X-Forwarded-Proto \$scheme;
        # proxy_read_timeout 3600;
        # proxy_pass_request_headers on;
    }
}
# FS
server {
    listen 7567;
    listen [::]:7567;
    server_name \$host;

    location / {
        proxy_pass http://127.0.0.1:3003;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        # proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        # proxy_set_header X-Forwarded-Proto \$scheme;
        # proxy_read_timeout 3600;
        # proxy_pass_request_headers on;
    }
}
EOF
    ln -fs /etc/nginx/sites-available/genieacs /etc/nginx/sites-enabled/genieacs
}

install_pre_reqs
install_nodeLTS
install_mongodb
install_genieacs
create_unit_files
config_log_rotation
install_nginx
restart_services

IPv4=$(ip -4 addr | grep -i inet | grep "scope global" | awk '{print $2}' | cut -d'/' -f1)
echo "#### GenieACS UI access: https://$IPv4 ####" | /usr/games/lolcat

unset SSL_COUNTRY_NAME
unset SSL_PROVINCE_NAME
unset SSL_LOCALITY_NAME
unset SSL_ORGANIZATION_NAME
unset SSL_ORGANIZATION_UNIT
unset SSL_COMMON_NAME
unset SSL_EMAIL_ADDRESS
unset IPv4
