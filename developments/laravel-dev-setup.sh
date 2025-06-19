#!/bin/bash

set -e

# === CONFIGURAÇÕES PERSONALIZÁVEIS ===
PHP_VERSION="8.4"
NODE_VERSION="22"
USUARIO="$(whoami)"
BASE_DIR="/home/$USUARIO/projects"
PROJETOS=("gym-management-system" "school-management-system" "api")
PORTAS=(8001 8002 8003)

echo "[1/9] Instalando Apache2..."
if ! dpkg -s apache2 &>/dev/null; then
    sudo apt update
    sudo apt install apache2 -y
fi

echo "[2/9] Ativando módulos do Apache..."
sudo a2enmod rewrite proxy proxy_http proxy_fcgi setenvif
sudo a2dismod mpm_event || true
sudo a2enmod mpm_prefork

echo "[3/9] Instalando PHP $PHP_VERSION e extensões..."
if ! dpkg -s php$PHP_VERSION &>/dev/null; then
    sudo add-apt-repository ppa:ondrej/php -y
    sudo sed -i 's/^Suites: oracular$/Suites: noble/' /etc/apt/sources.list.d/ondrej-ubuntu-php-oracular.sources || true
    sudo apt update
    sudo apt install -y php$PHP_VERSION libapache2-mod-php$PHP_VERSION \
      php$PHP_VERSION-{fpm,dev,common,xml,opcache,mbstring,zip,mysql,pgsql,curl,xdebug,redis,gd,bcmath,intl}
fi

sudo a2enconf php$PHP_VERSION-fpm
sudo systemctl restart apache2

echo "[4/9] Instalando Composer + Laravel Installer..."
if ! command -v composer >/dev/null; then
    curl -sS https://getcomposer.org/installer | php$PHP_VERSION
    sudo mv composer.phar /usr/local/bin/composer
fi

mkdir -p ~/.config/composer
cat <<EOF > ~/.config/composer/composer.json
{
    "require": {
        "php": "^$PHP_VERSION",
        "laravel/installer": "^5.10"
    }
}
EOF

cd ~/.config/composer && composer install && cd ~
grep -qxF 'export PATH="$PATH:$HOME/.config/composer/vendor/bin"' ~/.bashrc || echo 'export PATH="$PATH:$HOME/.config/composer/vendor/bin"' >> ~/.bashrc

echo "[5/9] Instalando NVM + Node.js $NODE_VERSION..."
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

source "$NVM_DIR/nvm.sh"
nvm install $NODE_VERSION
nvm use $NODE_VERSION
nvm alias default $NODE_VERSION

echo "[6/9] Instalando e configurando MySQL para desenvolvimento..."
if ! dpkg -s mysql-server &>/dev/null; then
    sudo apt update
    sudo apt install mysql-server -y
fi

sudo systemctl enable mysql
sudo systemctl start mysql

# Habilita login sem senha (ambiente local)
sudo sed -i 's/

\[mysqld\]

/[mysqld]\nskip-grant-tables\n/' /etc/mysql/mysql.conf.d/mysqld.cnf || true
sudo systemctl restart mysql

# Cria banco padrão e usuário 'dev'
mysql -u root <<MYSQL_SCRIPT
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS laravel_dev;
CREATE USER IF NOT EXISTS 'dev'@'localhost' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON laravel_dev.* TO 'dev'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo "[7/9] Verificando Supervisor..."
if ! command -v supervisorctl >/dev/null; then
    sudo apt install supervisor -y
fi

echo "[8/9] Criando configurações para Supervisor..."
for i in "${!PROJETOS[@]}"; do
    PROJ=${PROJETOS[$i]}
    PORTA=${PORTAS[$i]}
    DIR_PROJ="$BASE_DIR/$PROJ"
    CONF_FILE="/etc/supervisor/conf.d/laravel_$PROJ.conf"

    if [ ! -d "$DIR_PROJ" ]; then
        echo "⚠ Projeto '$DIR_PROJ' não encontrado. Pulando..."
        continue
    fi

    sudo tee "$CONF_FILE" > /dev/null <<EOF
[program:laravel_$PROJ]
command=/usr/bin/php$PHP_VERSION artisan serve --host=127.0.0.1 --port=$PORTA
directory=$DIR_PROJ
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/laravel_$PROJ.err.log
stdout_logfile=/var/log/supervisor/laravel_$PROJ.out.log
user=$USUARIO
EOF
done

sudo supervisorctl reread
sudo supervisorctl update

echo "[9/9] Gerando vhost Apache com proxy reverso para os projetos..."

VHOST="/etc/apache2/sites-available/laravel-dev.conf"
SOCKET="/run/php/php$PHP_VERSION-fpm.sock"

sudo tee "$VHOST" > /dev/null <<EOF
<VirtualHost *:80>
    ServerName localhost
    ProxyPreserveHost On
EOF

for i in "${!PROJETOS[@]}"; do
    PROJ=${PROJETOS[$i]}
    PORTA=${PORTAS[$i]}
    sudo tee -a "$VHOST" > /dev/null <<EOF
    ProxyPass /$PROJ http://127.0.0.1:$PORTA/
    ProxyPassReverse /$PROJ http://127.0.0.1:$PORTA/
EOF
done

sudo tee -a "$VHOST" > /dev/null <<EOF

    <FilesMatch \.php$>
        SetHandler "proxy:unix:$SOCKET|fcgi://localhost"
    </FilesMatch>
</VirtualHost>
EOF

sudo a2ensite laravel-dev.conf
sudo systemctl reload apache2

echo -e "\n✅ Ambiente Laravel com PHP $PHP_VERSION, Node.js $NODE_VERSION, MySQL e Supervisor está pronto para ação!"
for PROJ in "${PROJETOS[@]}"; do
    echo "🔗 http://localhost/$PROJ"
done