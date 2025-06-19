#!/usr/bin/bash

LOCKFILE="/tmp/developer_config.lock"

# Verifica se já existe uma instância rodando (ignora o próprio processo)
if [ -e "$LOCKFILE" ]; then
    CURRENT_PID=$$
    # Procura outros processos developer_config.sh, exceto o atual
    OTHER_PIDS=$(pgrep -f developer_config.sh | grep -vw "$CURRENT_PID" || true)
    if [ -n "$OTHER_PIDS" ]; then
        echo "O script já está em execução."
        echo -n "Deseja matar o(s) outro(s) processo(s) em execução? (y/n): "
        read choice
        if [[ "$choice" == "y" ]]; then
            echo "$OTHER_PIDS" | xargs -r kill
            sleep 2
            rm -f "$LOCKFILE"
            echo "Processo(s) encerrado(s). Você pode rodar o script novamente."
        else
            echo "Saindo..."
            exit 1
        fi
    fi
fi

touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"; exit' INT TERM EXIT

set -e

# Instala dependência para add-apt-repository e adiciona o PPA corretamente
sudo nala install -y software-properties-common

# php8.4
if ! dpkg -s php8.4 &>/dev/null; then
    sudo add-apt-repository ppa:ondrej/php -y
    
    # Corrige Suite do PPA ondrej/php para noble, se necessário
    PPA_FILE="/etc/apt/sources.list.d/ondrej-ubuntu-php-oracular.sources"
    if [ -f "$PPA_FILE" ]; then
        sudo sed -i 's/^Suites: oracular$/Suites: noble/' "$PPA_FILE"
    fi

    sudo nala update
    sudo nala install php8.4 libapache2-mod-php8.4 php8.4-{dev,common,xml,opcache,mbstring,zip,mysql,pgsql,curl,xdebug,redis,gd,bcmath,intl,fpm} unzip -y
else
    echo "php8.4 já está instalado."
fi


# habilitar o modo de reescrita de url do apache
if ! sudo a2query -m rewrite | grep -q 'enabled'; then
    sudo a2enmod rewrite
fi
if sudo a2query -m mpm_event | grep -q 'enabled'; then
    sudo a2dismod mpm_event
fi
if ! sudo a2query -m mpm_prefork | grep -q 'enabled'; then
    sudo a2enmod mpm_prefork
fi
if ! sudo a2query -m php8.4 | grep -q 'enabled'; then
    sudo a2enmod php8.4
fi
if ! sudo a2query -m proxy_fcgi | grep -q 'enabled'; then
    sudo a2enmod proxy_fcgi setenvif
fi
if [ ! -f /etc/apache2/conf-enabled/php8.4-fpm.conf ]; then
    sudo a2enconf php8.4-fpm
fi
sudo systemctl restart apache2

# Composer
if ! command -v composer > /dev/null; then
    curl -sS https://getcomposer.org/installer | php8.4 && sudo mv composer.phar /usr/local/bin/composer

    if [ ! -f /home/$USER/.config/composer/composer.json ]; then
        sudo touch /home/$USER/.config/composer/composer.json
        sudo chown -R $USER: /home/$USER/.config/composer
        sudo chmod 775 /home/$USER/.config/composer/composer.json
        echo '{
        \t"require": {
        \t\t"php": "^8.3",
        \t\t"laravel/installer": "^5.10"
        \t}
        }' >> /home/$USER/.config/composer/composer.json
    fi
    cd /home/$USER/.config/composer/ && composer install && cd ~

    echo "Composer instalado com sucesso."
    composer --version
else
    echo "Composer já está instalado."
fi

#---Setar variável de ambiente do composer global---
for PROFILE in ~/.bashrc ~/.zshrc; do
    # Remove comandos que produzem saída interativa
    sed -i '/^composer --version$/d' "$PROFILE"
    sed -i '/^laravel --version$/d' "$PROFILE"
    # Garante apenas o PATH do composer global
    if ! grep -Fxq 'export PATH="$PATH:$HOME/.config/composer/vendor/bin"' "$PROFILE"; then
        echo 'export PATH="$PATH:$HOME/.config/composer/vendor/bin"' >> "$PROFILE"
    fi
    # Não executa source automaticamente
    # O usuário pode abrir um novo terminal para carregar as alterações
    # echo "Alterações aplicadas ao $PROFILE. Abra um novo terminal para carregar."
done

#---Setar NVM no shell profile---
for PROFILE in ~/.bashrc ~/.zshrc; do
    if ! grep -Fxq 'export NVM_DIR="$HOME/.nvm"' "$PROFILE"; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> "$PROFILE"
    fi
    if ! grep -Fxq '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' "$PROFILE"; then
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$PROFILE"
    fi
    if ! grep -Fxq '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' "$PROFILE"; then
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> "$PROFILE"
    fi
    # Não executa source automaticamente
    # O usuário pode abrir um novo terminal para carregar as alterações
    # echo "NVM configurado em $PROFILE. Abra um novo terminal para carregar."
done

#* Instalar o nodejs e o npm
# Instala e configura NVM e Node.js 22
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    mkdir -p "$NVM_DIR"
fi

# Instala dependências se necessário
if ! command -v curl > /dev/null; then
    echo "cURL não encontrado. Instalando..."
    sudo apt install curl -y
fi

# Instalar o NVM se não existir
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

# Carregar NVM
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Instalar Node.js 22 se necessário
if ! command -v node > /dev/null || ! node -v | grep -q '^v22\.'; then
    nvm install 22
    nvm use 22
    nvm alias default 22
fi

# Exibir versões instaladas
node -v
npm -v


#* Link para a pasta FTP do Apache
if [ ! -d /var/www/html/ftp ]; then
    sudo mkdir -m755 /var/www/html/ftp
fi
if [ ! -d /home/$USER/ftp ]; then
    sudo mkdir -m755 /home/$USER/ftp
fi
sudo chown -R $USER: /var/www/html/ftp
sudo chown -R $USER: /home/$USER/ftp
if [ ! -L /home/$USER/ftp/public ]; then
    sudo ln -s /var/www/html/ftp /home/$USER/ftp/public
fi

# Acrescentar ou atualizar configurações no /etc/vsftpd.conf
update_vsftpd_conf() {
    local key="$1"
    local value="$2"
    local file="/etc/vsftpd.conf"
    if grep -q "^${key}=" "$file"; then
        sudo sed -i "s|^${key}=.*|${key}=${value}|g" "$file"
    else
        echo "${key}=${value}" | sudo tee -a "$file" > /dev/null
    fi
}

update_vsftpd_conf write_enable YES
update_vsftpd_conf chroot_local_user YES
update_vsftpd_conf allow_writeable_chroot YES
update_vsftpd_conf user_sub_token "$USER"
update_vsftpd_conf local_root "/home/$USER/ftp/public"

sudo systemctl restart vsftpd

#* Instalar PostgreSQL
if ! dpkg -s postgresql &>/dev/null; then
    sudo nala install postgresql -y
else
    echo "PostgreSQL já está instalado."
fi

# Instalar o PgAdmin4
if ! dpkg -s pgadmin4 &>/dev/null; then
    curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg
    echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" | sudo tee /etc/apt/sources.list.d/pgadmin4.list
    sudo nala update
    sudo nala install pgadmin4 -y
else
    echo "PgAdmin4 já está instalado."
fi

#* Habilitar o firewall na inicialização do sistema
if ! dpkg -s gufw &>/dev/null; then
    sudo nala install gufw -y
else
    echo "GUFW já está instalado."
fi
sudo ufw enable && 
sudo ufw default deny incoming && sudo ufw default allow outgoing

#Permissão para as portas
#!/bin/bash

# Verifica se o firewall está ativo
echo "Verificando status do UFW..."
sudo ufw status | grep -q "inactive" && sudo ufw enable

# Lista de portas a liberar
PORTS=(21 22 80 443 3306 5432 6379 9000 8080)

# Função para verificar se a regra já existe
ufw_rule_exists() {
    local port="$1"
    sudo ufw status | grep -qw ":$port"
}

echo "Configurando regras do firewall..."
for PORT in "${PORTS[@]}"; do
    if ufw_rule_exists "$PORT"; then
        echo "Regra para porta $PORT já existe. Pulando."
    else
        sudo ufw allow "${PORT}/tcp"
        echo "Regra adicionada para porta $PORT."
    fi
    # Pequeno delay para evitar race conditions
    sleep 0.2
done

# Recarrega UFW para aplicar regras
echo "Recarregando o firewall..."
sudo ufw reload

# Exibe status final
echo "Status atualizado do firewall:"
sudo ufw status verbose

#* Instalar acesso seguro - servidor (ssh)
if ! dpkg -s openssh-server &>/dev/null; then
    sudo nala install -y openssh-server
    sudo systemctl enable ssh && sudo systemctl restart ssh
else
    echo "OpenSSH Server já está instalado."
fi

#* Instalar Mysql Server
if ! dpkg -s mysql-server &>/dev/null; then
    sudo nala install mysql-server mysql-client -y

    # Alterar a senha do root no MySQL
    MYSQL_ROOT_PASSWORD=""

    sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';"
    sudo mysql -e "FLUSH PRIVILEGES;"

    echo "Senha do root do MySQL alterada com sucesso."
else
    echo "MySQL Server já está instalado."
fi


# instalação do phpmyadmin
if ! dpkg -s phpmyadmin &>/dev/null; then
    sudo nala install phpmyadmin -y
else
    echo "phpMyAdmin já está instalado."
fi

# Descomentar a linha AllowNoPassword no config.inc.php do phpMyAdmin
sudo sed -i "/AllowNoPassword/s|^\s*#\s*||" /etc/phpmyadmin/config.inc.php

# montagem de partições NTFS no linux
if [ ! -d /media/arquivos ]; then
    sudo mkdir -m775 /media/arquivos
    sudo chown -R $USER: /media/arquivos/
else
    echo "/media/arquivos já existe. Pulando criação."
fi
# Valida se já existe a entrada no fstab antes de adicionar
if ! grep -q '^UUID=0EF00CA20EF00CA2 /media/arquivos/ ntfs-3g defaults 0 0' /etc/fstab; then
    echo "UUID=0EF00CA20EF00CA2 /media/arquivos/ ntfs-3g defaults 0 0" | sudo tee -a /etc/fstab
else
    echo "Entrada do /media/arquivos já existe no /etc/fstab."
fi

#* Instalação do MinIO-Server
if ! command -v minio > /dev/null; then
    MINIO_DIR="/usr/local/bin"
    MINIO_BIN="$MINIO_DIR/minio"
    MINIO_URL="https://dl.min.io/server/minio/release/linux-amd64/minio"
    MINIO_SHA256_URL="https://dl.min.io/server/minio/release/linux-amd64/minio.sha256sum"
    MINIO_SERVICE="/etc/systemd/system/minio.service"
    TMP_MINIO="/tmp/minio"
    TMP_SHA256="/tmp/minio.sha256sum"

    echo "Baixando hash oficial do MinIO..."
    curl -fsSL "$MINIO_SHA256_URL" -o "$TMP_SHA256"

    # Função para validar hash
    validate_minio_hash() {
        local file="$1"
        local sha_file="$2"
        local expected actual
        expected=$(awk '{print $1}' "$sha_file")
        actual=$(sha256sum "$file" | awk '{print $1}')
        [ "$expected" = "$actual" ]
    }

    # Baixa o binário se não existir ou se o hash não bater
    if [ ! -f "$MINIO_BIN" ] || ! validate_minio_hash "$MINIO_BIN" "$TMP_SHA256"; then
        echo "Baixando MinIO..."
        curl -fsSL "$MINIO_URL" -o "$TMP_MINIO"
        if validate_minio_hash "$TMP_MINIO" "$TMP_SHA256"; then
            sudo mv "$TMP_MINIO" "$MINIO_BIN"
            sudo chmod +x "$MINIO_BIN"
            echo "MinIO baixado e validado com sucesso."
        else
            echo "Erro: hash SHA256 do MinIO não confere! Abortando."
            rm -f "$TMP_MINIO"
            exit 1
        fi
    else
        echo "MinIO já existe e hash está válido."
    fi

    # Cria diretório de armazenamento com sudo
    echo "Criando diretório para armazenar arquivos..."
    sudo mkdir -p /data/minio
    sudo chown -R $(whoami):$(whoami) /data/minio

    # Configura variável de ambiente para MinIO
    echo "Definindo variáveis de ambiente..."
    echo 'MINIO_ROOT_USER="admin"' | sudo tee /etc/default/minio > /dev/null
    echo 'MINIO_ROOT_PASSWORD="minio123"' | sudo tee -a /etc/default/minio > /dev/null
    echo 'MINIO_VOLUMES="/data/minio"' | sudo tee -a /etc/default/minio > /dev/null
    echo 'MINIO_SERVER_URL="http://127.0.0.1:9000"' | sudo tee -a /etc/default/minio > /dev/null

    # Criação do serviço systemd
    echo "Criando serviço systemd para MinIO..."
    sudo tee "$MINIO_SERVICE" > /dev/null <<EOF
[Unit]
Description=MinIO Storage Server
After=network.target

[Service]
EnvironmentFile=/etc/default/minio
ExecStart=$MINIO_BIN server \$MINIO_VOLUMES
Restart=always
User=$(whoami)
Group=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

    # Habilita e inicia o serviço
    echo "Habilitando e iniciando MinIO..."
    sudo systemctl daemon-reload
    sudo systemctl enable minio
    sudo systemctl start minio

    # Exibe status
    echo "Verificando status do serviço MinIO..."
    sudo systemctl status minio --no-pager

    echo "MinIO instalado com sucesso!"
    echo "Acesse via navegador: http://127.0.0.1:9000"
else
    echo "MinIO já está instalado. Validando integridade..."
    MINIO_BIN="/usr/local/bin/minio"
    MINIO_SHA256_URL="https://dl.min.io/server/minio/release/linux-amd64/minio.sha256sum"
    TMP_SHA256="/tmp/minio.sha256sum"
    curl -fsSL "$MINIO_SHA256_URL" -o "$TMP_SHA256"
    expected=$(awk '{print $1}' "$TMP_SHA256")
    actual=$(sha256sum "$MINIO_BIN" | awk '{print $1}')
    if [ "$expected" != "$actual" ]; then
        echo "Hash do MinIO está incorreto. Baixando novamente..."
        curl -fsSL "https://dl.min.io/server/minio/release/linux-amd64/minio" -o /tmp/minio
        if [ "$(sha256sum /tmp/minio | awk '{print $1}')" = "$expected" ]; then
            sudo mv /tmp/minio "$MINIO_BIN"
            sudo chmod +x "$MINIO_BIN"
            echo "MinIO atualizado com sucesso."
            sudo systemctl restart minio
        else
            echo "Erro: hash SHA256 do MinIO não confere! Abortando."
            rm -f /tmp/minio
            exit 1
        fi
    else
        echo "Hash do MinIO está válido."
    fi
fi

#* Instalação do Docker
DOCKER_OK=false
if dpkg -s docker-ce &>/dev/null && command -v docker > /dev/null; then
    if sudo systemctl is-active --quiet docker; then
        if docker info > /dev/null 2>&1; then
            DOCKER_OK=true
        fi
    fi
fi

if [ "$DOCKER_OK" = false ]; then
    echo "Instalando ou corrigindo Docker..."
    sudo nala update
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo nala update
    sudo nala install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    sudo groupadd docker || true
    sudo usermod -aG docker $USER
    newgrp docker
    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service
    sudo systemctl restart docker
    sleep 2
    if command -v docker > /dev/null && sudo systemctl is-active --quiet docker && docker info > /dev/null 2>&1; then
        echo "Docker instalado e funcional."
    else
        echo "Erro: Docker não está funcional após instalação. Verifique manualmente."
        exit 1
    fi
else
    echo "Docker já está instalado e funcional."
fi

sudo touch /var/www/html/phpinfo.php
echo "<?php phpinfo(); ?>" | sudo tee -a /var/www/html/info.php

sudo nala upgrade -y
sudo nala autoremove -y

echo "Instalação concluída!"