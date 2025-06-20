#!/usr/bin/bash

source "$(dirname "$0")/../common/functions.sh"
source "$(dirname "$0")/../common/config.sh"

# Função para validar e ajustar repositórios PHP
validate_php_repositories() {
    local SOURCES_FILE="/etc/apt/sources.list.d/ondrej-ubuntu-php-plucky.sources"
    local BACKUP_FILE="${SOURCES_FILE}.bak"

    echo "🔍 Validando repositórios PHP..."

    # Criar backup se o arquivo existir e não houver backup
    if [ -f "$SOURCES_FILE" ] && [ ! -f "$BACKUP_FILE" ]; then
        sudo cp "$SOURCES_FILE" "$BACKUP_FILE"
        echo "📦 Backup do arquivo de repositórios criado: $BACKUP_FILE"
    fi

    # Verificar e ajustar o arquivo de repositório
    if [ -f "$SOURCES_FILE" ]; then
        # Verificar se precisa ajustar o Suite para noble
        if grep -q "^Suites: plucky" "$SOURCES_FILE"; then
            echo "🔧 Ajustando Suite para noble no arquivo de repositórios..."
            sudo sed -i 's/^Suites: plucky/Suites: noble/' "$SOURCES_FILE"
            sudo apt update
            echo "✅ Repositórios PHP atualizados com sucesso!"
        elif grep -q "^Suites: noble" "$SOURCES_FILE"; then
            echo "✅ Repositórios PHP já estão configurados corretamente!"
        else
            echo "⚠️ Configuração de Suite não encontrada, adicionando..."
            echo "Suites: noble" | sudo tee -a "$SOURCES_FILE" > /dev/null
            sudo apt update
            echo "✅ Repositórios PHP configurados com sucesso!"
        fi
    else
        echo "❌ Arquivo de configuração do PHP não encontrado: $SOURCES_FILE"
        echo "ℹ️  Certifique-se de que o repositório ondrej/php foi adicionado corretamente"
        return 1
    fi
}

setup_php_environment() {
    local PHP_VERSION="8.4"
    local ERROR_COUNT=0
    
    echo "🐘 Configurando ambiente PHP $PHP_VERSION..."
    
    # Verificar se o PHP já está instalado na versão correta
    if command -v php > /dev/null && php -v | grep -q "PHP $PHP_VERSION"; then
        echo "✅ PHP $PHP_VERSION já está instalado!"
        return 0
    fi
    
    # Validar repositórios antes da instalação
    validate_php_repositories || {
        echo "❌ Falha ao validar repositórios PHP"
        return 1
    }
    
    echo "📦 Instalando PHP e extensões..."
    
    # Lista de pacotes PHP necessários
    local PHP_PACKAGES=(
        "php$PHP_VERSION"
        "php$PHP_VERSION-cli"
        "php$PHP_VERSION-dev"
        "php$PHP_VERSION-common"
        "php$PHP_VERSION-xml"
        "php$PHP_VERSION-opcache"
        "php$PHP_VERSION-mbstring"
        "php$PHP_VERSION-mysql"
        "php$PHP_VERSION-pgsql"
        "php$PHP_VERSION-curl"
        "php$PHP_VERSION-xdebug"
        "php$PHP_VERSION-redis"
        "php$PHP_VERSION-gd"
        "php$PHP_VERSION-bcmath"
        "php$PHP_VERSION-fpm"
        "php$PHP_VERSION-zip"
        "php$PHP_VERSION-intl"
    )
    
    # Instalar pacotes PHP
    for package in "${PHP_PACKAGES[@]}"; do
        echo "🔄 Instalando $package..."
        if ! sudo apt install -y "$package"; then
            echo "⚠️ Falha ao instalar $package"
            ((ERROR_COUNT++))
        fi
    done
    
    # Verificar resultado final
    if [ $ERROR_COUNT -eq 0 ]; then
        # Configurar PHP-FPM no Apache se ambos estiverem instalados
        if systemctl is-active --quiet apache2; then
            configure_apache_fpm "$PHP_VERSION" || ((ERROR_COUNT++))
        fi
        
        if [ $ERROR_COUNT -eq 0 ]; then
            echo "✅ Ambiente PHP configurado com sucesso!"
            # Mostrar versão instalada
            php -v
            return 0
        fi
    fi
    
    echo "⚠️ Instalação concluída com $ERROR_COUNT erro(s)"
    echo "📋 Por favor, verifique as mensagens acima"
    return 1
}

setup_web_server() {
    echo "🌐 Configurando servidor web..."
    local ERROR_COUNT=0
    
    # Verificar Apache
    if systemctl is-active --quiet apache2; then
        echo "✅ Apache já está instalado e rodando!"
    else
        echo "📦 Instalando Apache..."
        install_package "apache2" || ((ERROR_COUNT++))
        
        if [ $ERROR_COUNT -eq 0 ]; then
            echo "🔧 Configurando módulos Apache..."
            sudo a2enmod rewrite proxy proxy_http
            
            # Configurar PHP-FPM se o PHP estiver instalado
            if command -v php > /dev/null; then
                PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
                configure_apache_fpm "$PHP_VERSION" || ((ERROR_COUNT++))
            else
                # Configuração padrão se PHP não estiver instalado
                sudo a2enmod proxy_fcgi setenvif
                sudo a2dismod mpm_event || true
                sudo a2enmod mpm_prefork
            fi
        fi
    fi
    
    # Verificar VSFTPD
    if systemctl is-active --quiet vsftpd; then
        echo "✅ VSFTPD já está instalado e rodando!"
    else
        echo "📦 Instalando VSFTPD..."
        install_package "vsftpd" || ((ERROR_COUNT++))
    fi
    
    if [ $ERROR_COUNT -eq 0 ]; then
        setup_ftp_directories
        configure_vsftpd
        echo "✅ Servidor web configurado com sucesso!"
    else
        echo "⚠️ Configuração concluída com $ERROR_COUNT erro(s)"
        return 1
    fi
}

setup_ftp_directories() {
    local FTP_DIRS=(
        "/var/www/html/ftp"
        "/home/$USER/ftp"
    )
    
    for dir in "${FTP_DIRS[@]}"; do
        ensure_dir "$dir"
        sudo chmod 755 "$dir"
        sudo chown -R $USER: "$dir"
    done
    
    if [ ! -L "/home/$USER/ftp/public" ]; then
        sudo ln -s "/var/www/html/ftp" "/home/$USER/ftp/public"
    fi
}

configure_vsftpd() {
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
}

setup_node_environment() {
    local NODE_VERSION="22"
    echo "📦 Configurando Node.js $NODE_VERSION..."
    
    # Verificar se NVM já está instalado
    export NVM_DIR="$HOME/.nvm"
    if [ -d "$NVM_DIR" ]; then
        source "$NVM_DIR/nvm.sh" || true
        
        # Verificar se a versão correta do Node está instalada
        if command -v node > /dev/null && node -v | grep -q "v$NODE_VERSION"; then
            echo "✅ Node.js $NODE_VERSION já está instalado!"
            return 0
        fi
    fi
    
    echo "📦 Instalando NVM e Node.js $NODE_VERSION..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    
    # Recarregar NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
    
    if command -v nvm > /dev/null; then
        nvm install $NODE_VERSION
        nvm use $NODE_VERSION
        nvm alias default $NODE_VERSION
        
        if node -v | grep -q "v$NODE_VERSION"; then
            echo "✅ Node.js $NODE_VERSION instalado com sucesso!"
        else
            echo "❌ Falha ao instalar Node.js $NODE_VERSION"
            return 1
        fi
    else
        echo "❌ Falha ao instalar NVM"
        return 1
    fi
}

setup_databases() {
    echo "🗄️ Configurando bancos de dados..."
    local ERROR_COUNT=0
    
    # PostgreSQL
    if systemctl is-active --quiet postgresql; then
        echo "✅ PostgreSQL já está instalado e rodando!"
    else
        echo "📦 Instalando PostgreSQL..."
        install_package "postgresql" || ((ERROR_COUNT++))
    fi
    
    # Redis
    if systemctl is-active --quiet redis-server; then
        echo "✅ Redis já está instalado e rodando!"
    else
        echo "📦 Instalando Redis..."
        install_package "redis" || ((ERROR_COUNT++))
    fi
    
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Bancos de dados configurados com sucesso!"
    else
        echo "⚠️ Instalação concluída com $ERROR_COUNT erro(s)"
        return 1
    fi
}

install_dev_tools() {
    echo "🔨 Instalando ferramentas de desenvolvimento..."
    local ERROR_COUNT=0
    
    # Chrome
    if command -v google-chrome > /dev/null; then
        echo "✅ Google Chrome já está instalado!"
    else
        echo "📦 Instalando Google Chrome..."
        install_chrome || ((ERROR_COUNT++))
    fi
    
    # VSCode
    if command -v code > /dev/null; then
        echo "✅ Visual Studio Code já está instalado!"
    else
        echo "📦 Instalando Visual Studio Code..."
        install_vscode || ((ERROR_COUNT++))
    fi
    
    # Cursor
    if command -v cursor > /dev/null; then
        echo "✅ Cursor já está instalado!"
    else
        echo "📦 Instalando Cursor..."
        install_cursor || ((ERROR_COUNT++))
    fi
    
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Todas as ferramentas de desenvolvimento foram instaladas com sucesso!"
    else
        echo "⚠️ Instalação concluída com $ERROR_COUNT erro(s)"
        return 1
    fi
}

# Função auxiliar para configurar shell RC files
configure_shell_rc() {
    local config_content="$1"
    local error_count=0
    
    # Array com os arquivos RC e seus backups
    declare -A RC_FILES=(
        ["$HOME/.bashrc"]="$HOME/.bashrc.bak"
        ["$HOME/.zshrc"]="$HOME/.zshrc.bak"
    )
    
    # Função para adicionar configuração se não existir
    add_config_if_missing() {
        local rc_file="$1"
        local backup_file="$2"
        local added=0
        
        # Criar arquivo se não existir
        if [ ! -f "$rc_file" ]; then
            touch "$rc_file" || return 1
        fi
        
        # Verificar permissões
        if [ ! -w "$rc_file" ]; then
            echo "❌ Sem permissão de escrita em $rc_file"
            return 1
        fi
        
        # Criar backup se não existir
        if [ ! -f "$backup_file" ]; then
            cp "$rc_file" "$backup_file" || return 1
            echo "📦 Backup criado: $backup_file"
        fi
        
        # Adicionar configuração se não existir
        if ! grep -q "\.bash_aliases" "$rc_file"; then
            echo "📝 Adicionando configuração em $rc_file..."
            echo "$config_content" >> "$rc_file" || return 1
            added=1
        fi
        
        return $added
    }
    
    echo "🔧 Configurando arquivos RC..."
    
    # Processar cada arquivo RC
    for rc_file in "${!RC_FILES[@]}"; do
        local backup_file="${RC_FILES[$rc_file]}"
        
        if add_config_if_missing "$rc_file" "$backup_file"; then
            echo "✅ Configuração adicionada em $rc_file"
        else
            echo "ℹ️ Configuração já existe em $rc_file"
        fi || {
            echo "❌ Erro ao configurar $rc_file"
            ((error_count++))
        }
    done
    
    return $error_count
}

configure_dev_aliases() {
    local ALIASES_FILE="/home/$USER/.bash_aliases"
    local RC_ERROR=0

    echo "🔍 Verificando arquivo de aliases..."
    
    # Garantir que o diretório home existe e temos permissão
    if [ ! -w "$HOME" ]; then
        echo "❌ Sem permissão de escrita no diretório home"
        return 1
    fi

    # Conteúdo dos aliases
    local ALIASES_CONTENT="# Package Management
alias update=\"sudo sudo apt install update\"
alias upgrade=\"sudo sudo apt install upgrade -y\"
alias sudo apt installi=\"sudo sudo apt install install -y\"

# PHP/Laravel
alias art=\"php artisan\"
alias ci=\"composer install\"
alias cu=\"composer update\"
alias cr=\"composer remove\"
alias cda=\"composer dump-autoload -o\"
alias sail='sh \$([ -f sail ] && echo sail || echo vendor/bin/sail)'

# Node.js/NPM
alias ni=\"npm install\"
alias nu=\"npm update\"
alias nrd=\"npm run dev\"
alias nrb=\"npm run build\"

# Git aliases
alias gs=\"git status\"
alias gl=\"git log\"
alias gp=\"git pull\"
alias gps=\"git push\"
alias gc=\"git commit -m\"
alias ga=\"git add\"
alias gaa=\"git add --all\"

# Docker aliases
alias dc=\"docker-compose\"
alias dcup=\"docker-compose up -d\"
alias dcdown=\"docker-compose down\"
alias dps=\"docker ps\"

# Utilidades
alias ll=\"ls -la\"
alias cls=\"clear\"
alias ..=\"cd ..\"
alias ...=\"cd ../..\"
alias reload=\"source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null\"

# NVM Configuration
export NVM_DIR=\"\$([ -z \"\${XDG_CONFIG_HOME-}\" ] && printf %s \"\${HOME}/.nvm\" || printf %s \"\${XDG_CONFIG_HOME}/nvm\")\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\" # This loads nvm"

    # Criar ou atualizar arquivo de aliases
    if [ -f "$ALIASES_FILE" ]; then
        echo "📝 Arquivo .bash_aliases encontrado, fazendo backup..."
        if ! cp "$ALIASES_FILE" "${ALIASES_FILE}.bak"; then
            echo "❌ Falha ao criar backup do arquivo de aliases"
            return 1
        fi
        echo "📦 Backup criado: ${ALIASES_FILE}.bak"
    fi

    # Tentar escrever o novo conteúdo
    if ! echo "$ALIASES_CONTENT" > "$ALIASES_FILE"; then
        echo "❌ Falha ao escrever arquivo de aliases"
        return 1
    fi

    # Verificar se o arquivo foi escrito corretamente
    if [ ! -f "$ALIASES_FILE" ]; then
        echo "❌ Arquivo de aliases não foi criado"
        return 1
    fi

    # Configuração para os arquivos RC
    local RC_CONFIG="
# Alias definitions
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi"

    # Configurar bash e zsh
    configure_shell_rc "$RC_CONFIG" || RC_ERROR=1

    # Tentar carregar aliases no ambiente atual
    if [ -f "$ALIASES_FILE" ]; then
        . "$ALIASES_FILE" 2>/dev/null || true
    fi

    if [ $RC_ERROR -eq 0 ]; then
        echo "✅ Aliases configurados com sucesso!"
        echo "ℹ️  Use o comando 'reload' para carregar as novas configurações"
        echo "   ou abra um novo terminal"
        return 0
    else
        echo "⚠️ Alguns erros ocorreram durante a configuração"
        echo "ℹ️  Execute 'source ~/.bashrc' ou 'source ~/.zshrc' manualmente"
        return 1
    fi
}

# Função para configurar PHP-FPM no Apache
configure_apache_fpm() {
    local PHP_VERSION=$1
    echo "🔧 Configurando Apache para usar PHP-FPM $PHP_VERSION..."
    
    # Habilitar módulos necessários
    sudo a2enmod proxy_fcgi setenvif
    sudo a2enconf "php$PHP_VERSION-fpm"
    
    # Verificar configuração do PHP-FPM
    if ! systemctl is-active --quiet "php$PHP_VERSION-fpm"; then
        echo "🔄 Iniciando serviço PHP-FPM..."  
        sudo systemctl start "php$PHP_VERSION-fpm"
        sudo systemctl enable "php$PHP_VERSION-fpm"
    fi
    
    # Reiniciar Apache para aplicar as mudanças
    echo "🔄 Reiniciando Apache..."
    sudo systemctl restart apache2
    
    # Verificar status dos serviços
    if systemctl is-active --quiet apache2 && systemctl is-active --quiet "php$PHP_VERSION-fpm"; then
        echo "✅ Apache configurado com PHP-FPM $PHP_VERSION com sucesso!"
        return 0
    else
        echo "❌ Erro na configuração do Apache com PHP-FPM"
        return 1
    fi
}

# Função para configurar MySQL em modo desenvolvimento
setup_mysql() {
    echo "🐬 Configurando MySQL para desenvolvimento..."
    
    # Instalar MySQL se não estiver instalado
    if ! dpkg -s mysql-server &>/dev/null; then
        echo "📦 Instalando MySQL Server..."
        install_package "mysql-server" || return 1
    else
        echo "✅ MySQL já está instalado!"
    fi
    
    # Habilitar e iniciar o serviço
    sudo systemctl enable mysql
    sudo systemctl start mysql
    
    # Habilitar login sem senha (ambiente local)
    local MYSQL_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"
    if ! grep -q "skip-grant-tables" "$MYSQL_CONF"; then
        echo "🔧 Configurando MySQL para modo desenvolvimento..."
        sudo sed -i '/^\[mysqld\]/a skip-grant-tables' "$MYSQL_CONF"
        sudo systemctl restart mysql
    fi
    
    # Criar banco padrão e usuário 'dev'
    echo "🔧 Configurando banco de dados e usuário padrão..."
    mysql -u root <<MYSQL_SCRIPT
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS laravel_dev;
CREATE USER IF NOT EXISTS 'dev'@'localhost' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON laravel_dev.* TO 'dev'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
    
    if [ $? -eq 0 ]; then
        echo "✅ MySQL configurado com sucesso!"
        return 0
    else
        echo "❌ Erro ao configurar MySQL"
        return 1
    fi
}

# Função para configurar Laravel e Composer
setup_laravel() {
    local PHP_VERSION=$1
    echo "🚀 Configurando Laravel e Composer..."
    
    # Instalar Composer se não estiver instalado
    if ! command -v composer >/dev/null; then
        echo "📦 Instalando Composer..."
        curl -sS https://getcomposer.org/installer | php$PHP_VERSION
        sudo mv composer.phar /usr/local/bin/composer
    else
        echo "✅ Composer já está instalado!"
    fi
    
    # Configurar Composer e Laravel Installer
    echo "🔧 Configurando Laravel Installer..."
    mkdir -p ~/.config/composer
    cat <<EOF > ~/.config/composer/composer.json
{
    "require": {
        "php": "^$PHP_VERSION",
        "laravel/installer": "^5.10"
    }
}
EOF
    
    (cd ~/.config/composer && composer install)
    
    # Adicionar composer vendor/bin ao PATH
    if ! grep -q 'export PATH="$PATH:$HOME/.config/composer/vendor/bin"' ~/.bashrc; then
        echo 'export PATH="$PATH:$HOME/.config/composer/vendor/bin"' >> ~/.bashrc
    fi
    
    echo "✅ Laravel e Composer configurados com sucesso!"
}

# Função para configurar Supervisor para projetos Laravel
setup_supervisor() {
    local PHP_VERSION=$1
    local USER=$2
    local BASE_DIR="/home/$USER/projects"
    local PROJETOS=("gym-management-system" "school-management-system" "api")
    local PORTAS=(8001 8002 8003)
    
    echo "👀 Configurando Supervisor..."
    
    # Instalar Supervisor se necessário
    if ! command -v supervisorctl >/dev/null; then
        echo "📦 Instalando Supervisor..."
        install_package "supervisor" || return 1
    else
        echo "✅ Supervisor já está instalado!"
    fi
    
    # Criar configurações para cada projeto
    echo "🔧 Configurando projetos no Supervisor..."
    for i in "${!PROJETOS[@]}"; do
        local PROJ=${PROJETOS[$i]}
        local PORTA=${PORTAS[$i]}
        local DIR_PROJ="$BASE_DIR/$PROJ"
        local CONF_FILE="/etc/supervisor/conf.d/laravel_$PROJ.conf"
        
        if [ ! -d "$DIR_PROJ" ]; then
            echo "⚠️ Projeto '$DIR_PROJ' não encontrado. Pulando..."
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
user=$USER
EOF
    done
    
    # Recarregar configurações
    sudo supervisorctl reread
    sudo supervisorctl update
    
    echo "✅ Supervisor configurado com sucesso!"
}

# Função para configurar VHost Apache com proxy reverso
configure_laravel_vhost() {
    local PHP_VERSION=$1
    local PROJETOS=("gym-management-system" "school-management-system" "api")
    local PORTAS=(8001 8002 8003)
    local VHOST="/etc/apache2/sites-available/laravel-dev.conf"
    local SOCKET="/run/php/php$PHP_VERSION-fpm.sock"
    
    echo "🌐 Configurando VHost Apache com proxy reverso..."
    
    # Criar configuração base do VHost
    sudo tee "$VHOST" > /dev/null <<EOF
<VirtualHost *:80>
    ServerName localhost
    ProxyPreserveHost On
EOF
    
    # Adicionar configuração para cada projeto
    for i in "${!PROJETOS[@]}"; do
        local PROJ=${PROJETOS[$i]}
        local PORTA=${PORTAS[$i]}
        
        sudo tee -a "$VHOST" > /dev/null <<EOF
    
    ProxyPass /$PROJ http://127.0.0.1:$PORTA/
    ProxyPassReverse /$PROJ http://127.0.0.1:$PORTA/
EOF
    done
    
    # Finalizar configuração do VHost
    sudo tee -a "$VHOST" > /dev/null <<EOF
    
    <FilesMatch \.php$>
        SetHandler "proxy:unix:$SOCKET|fcgi://localhost"
    </FilesMatch>
</VirtualHost>
EOF
    
    # Ativar o site e recarregar Apache
    sudo a2ensite laravel-dev.conf
    sudo systemctl reload apache2
    
    echo "✅ VHost Apache configurado com sucesso!"
    echo -e "\n🔗 URLs dos projetos:"
    for PROJ in "${PROJETOS[@]}"; do
        echo "http://localhost/$PROJ"
    done
}

# Função auxiliar para verificar dependências
check_dependencies() {
    local DEPS=("curl" "wget" "apt-transport-https" "ca-certificates" "software-properties-common")
    local MISSING=()

    echo "🔍 Verificando dependências básicas..."
    
    for dep in "${DEPS[@]}"; do
        if ! command -v "$dep" &>/dev/null && ! dpkg -s "$dep" &>/dev/null; then
            MISSING+=("$dep")
        fi
    done
    
    if [ ${#MISSING[@]} -gt 0 ]; then
        echo "📦 Instalando dependências faltantes: ${MISSING[*]}"
        sudo apt update
        sudo apt install -y "${MISSING[@]}" || return 1
    fi
    
    return 0
}

# Configuração do ambiente de desenvolvimento completo
setup_dev_environment() {
    echo "🚀 Iniciando configuração completa do ambiente de desenvolvimento..."
    local ERROR_COUNT=0
    local PHP_VERSION="8.4"
    local USER="$(whoami)"
    local START_TIME=$(date +%s)

    # Verificar dependências básicas primeiro
    check_dependencies || {
        echo "❌ Falha ao instalar dependências básicas"
        return 1
    }

    # Array para armazenar mensagens de erro
    declare -a ERROR_MESSAGES=()

    # Função auxiliar para executar e registrar erros
    run_step() {
        local step_name="$1"
        local step_func="$2"
        shift 2
        
        echo -e "\n📋 Executando: $step_name..."
        if ! $step_func "$@"; then
            ((ERROR_COUNT++))
            ERROR_MESSAGES+=("❌ Falha em: $step_name")
            return 1
        fi
        return 0
    }

    # Executar cada etapa com tratamento de erro
    run_step "Configuração de Aliases" configure_dev_aliases
    run_step "Ambiente PHP" setup_php_environment
    run_step "Servidor Web" setup_web_server
    run_step "Node.js" setup_node_environment
    run_step "Bancos de dados" setup_databases
    run_step "MySQL" setup_mysql
    run_step "Laravel e Composer" setup_laravel "$PHP_VERSION"
    run_step "Supervisor" setup_supervisor "$PHP_VERSION" "$USER"
    run_step "VHost Laravel" configure_laravel_vhost "$PHP_VERSION"
    run_step "Ferramentas de Desenvolvimento" install_dev_tools

    # Calcular tempo de execução
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    local MINUTES=$((DURATION / 60))
    local SECONDS=$((DURATION % 60))

    echo -e "\n📊 Relatório de Instalação"
    echo "⏱️  Tempo total: ${MINUTES}m ${SECONDS}s"

    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Ambiente de desenvolvimento configurado com sucesso!"
        echo -e "\n📝 Próximos passos:"
        echo "1. Execute 'source ~/.bashrc' para carregar os novos aliases"
        echo "2. Verifique os serviços com 'systemctl status apache2 mysql php$PHP_VERSION-fpm'"
        echo "3. Acesse http://localhost para testar o Apache"
        return 0
    else
        echo "⚠️ Configuração concluída com $ERROR_COUNT erro(s)"
        echo -e "\n❌ Erros encontrados:"
        printf '%s\n' "${ERROR_MESSAGES[@]}"
        echo -e "\n🔧 Sugestões de correção:"
        echo "1. Execute 'sudo apt update' e tente novamente"
        echo "2. Verifique se você tem permissões de sudo"
        echo "3. Verifique a conexão com a internet"
        echo "4. Tente executar cada componente individualmente pelo menu"
        return 1
    fi
}

# Menu de desenvolvimento
show_dev_menu() {
    echo -e "\n${BLUE}Escolha o que deseja configurar:${NC}"
    echo -e "${GREEN}1)${NC} Configurar Aliases de Desenvolvimento"
    echo -e "${GREEN}2)${NC} Ambiente PHP/Laravel"
    echo -e "${GREEN}3)${NC} Servidor Web (Apache/FTP)"
    echo -e "${GREEN}4)${NC} Node.js"
    echo -e "${GREEN}5)${NC} Bancos de dados"
    echo -e "${GREEN}6)${NC} Ferramentas de desenvolvimento"
    echo -e "${GREEN}7)${NC} MySQL para Desenvolvimento"
    echo -e "${GREEN}8)${NC} Laravel e Composer"
    echo -e "${GREEN}9)${NC} Configurar Supervisor"
    echo -e "${GREEN}10)${NC} Configurar VHost Laravel"
    echo -e "${GREEN}11)${NC} Configurar TUDO"
    echo -e "${GREEN}0)${NC} Voltar"
    
    read -r choice
    case $choice in
        1) configure_dev_aliases ;;
        2) setup_php_environment ;;
        3) setup_web_server ;;
        4) setup_node_environment ;;
        5) setup_databases ;;
        6) install_dev_tools ;;
        7) setup_mysql ;;
        8) setup_laravel "8.4" ;;
        9) setup_supervisor "8.4" "$(whoami)" ;;
        10) configure_laravel_vhost "8.4" ;;
        11) setup_dev_environment ;;
        0) return ;;
        *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
}

# Execução principal
check_root
show_dev_menu
