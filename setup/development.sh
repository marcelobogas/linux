#!/usr/bin/bash

source "$(dirname "$0")/../common/functions.sh"
source "$(dirname "$0")/../common/config.sh"

# Função para validar e ajustar repositórios PHP
CODENAME=noble

validate_php_repositories() {
    local ORIGINAL_CODENAME=$(lsb_release -cs)
    local SOURCES_FILE="/etc/apt/sources.list.d/ondrej-ubuntu-php-${ORIGINAL_CODENAME}.sources"
    local TARGET_FILE="/etc/apt/sources.list.d/ondrej-ubuntu-php-$CODENAME.sources"
    local BACKUP_FILE="${TARGET_FILE}.bak"

    echo "🔍 Validando repositório PHP (.sources)..."

    # Adicionar o repositório caso não exista nenhum arquivo correspondente
    if [ ! -f "$SOURCES_FILE" ] && [ ! -f "$TARGET_FILE" ]; then
        sudo add-apt-repository -y ppa:ondrej/php
        echo "✅ Repositório PHP adicionado!"
    fi

    # Se ainda existir o arquivo com codename original, renomear para usar 'noble'
    if [ -f "$SOURCES_FILE" ] && [ ! -f "$TARGET_FILE" ]; then
        sudo mv "$SOURCES_FILE" "$TARGET_FILE"
        echo "📁 Renomeado: $SOURCES_FILE → $TARGET_FILE"
    fi

    # Criar backup, se necessário
    if [ -f "$TARGET_FILE" ] && [ ! -f "$BACKUP_FILE" ]; then
        sudo cp "$TARGET_FILE" "$BACKUP_FILE"
        echo "📦 Backup criado: $BACKUP_FILE"
    fi

    # Ajustar a linha "Suites:" para o codename desejado
    if grep -q "^Suites:" "$TARGET_FILE"; then
        if grep -q "^Suites: $CODENAME" "$TARGET_FILE"; then
            echo "✅ Repositório já usa 'Suites: $CODENAME'."
        else
            echo "🔧 Corrigindo 'Suites' para '$CODENAME'..."
            sudo sed -i "s/^Suites:.*/Suites: $CODENAME/" "$TARGET_FILE"
            sudo apt update
            echo "✅ Suite atualizado para '$CODENAME'."
        fi
    else
        echo "⚠️ Linha 'Suites:' não encontrada. Adicionando..."
        echo "Suites: $CODENAME" | sudo tee -a "$TARGET_FILE" > /dev/null
        sudo apt update
        echo "✅ Linha 'Suites: $CODENAME' adicionada!"
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
    
    # Instalar ou verificar pacotes PHP
    for package in "${PHP_PACKAGES[@]}"; do
        if check_package_installed "$package"; then
            echo "✅ Pacote $package já está instalado"
        else
            echo "🔄 Instalando $package..."
            if ! sudo apt install -y "$package"; then
                echo "⚠️ Falha ao instalar $package"
                ((ERROR_COUNT++))
            fi
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
    if check_package_installed "apache2"; then
        echo "✅ Apache já está instalado!"
        
        # Verificar e habilitar módulos necessários
        if ! a2query -m proxy; then
            sudo a2enmod proxy proxy_http
            sudo a2enmod proxy_fcgi setenvif
            sudo a2dismod mpm_event || true
            sudo a2enmod mpm_prefork
            sudo systemctl restart apache2
        fi
    else
        install_package "apache2" || ((ERROR_COUNT++))
    fi
    
    # Verificar VSFTPD
    if systemctl is-active --quiet vsftpd; then
        echo "✅ VSFTPD já está instalado e rodando!"
    else
        install_package "vsftpd" || ((ERROR_COUNT++))
    fi
    
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Servidor web configurado com sucesso!"
        return 0
    fi
    
    return 1
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
    local ERROR_COUNT=0
    
    echo "� Verificando ambiente Node.js..."
    
    # Verificar NVM e Node.js
    export NVM_DIR="$HOME/.nvm"
    if [ -d "$NVM_DIR" ]; then
        echo "✅ NVM já está instalado"
        source "$NVM_DIR/nvm.sh" || true
        
        if command -v node > /dev/null; then
            local CURRENT_VERSION=$(node -v | cut -d'v' -f2)
            if [ "$CURRENT_VERSION" = "$NODE_VERSION" ]; then
                echo "✅ Node.js $NODE_VERSION já está instalado e ativo!"
                return 0
            else
                echo "ℹ️ Node.js $CURRENT_VERSION encontrado, atualizando para $NODE_VERSION..."
            fi
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
    if check_package_installed "postgresql"; then
        echo "✅ PostgreSQL já está instalado"
        if ! systemctl is-active --quiet postgresql; then
            echo "🔄 Iniciando serviço PostgreSQL..."
            sudo systemctl start postgresql || ((ERROR_COUNT++))
            sudo systemctl enable postgresql || ((ERROR_COUNT++))
        fi
    else
        echo "📦 Instalando PostgreSQL..."
        install_package "postgresql" || ((ERROR_COUNT++))
        if [ $ERROR_COUNT -eq 0 ]; then
            echo "🔄 Iniciando serviço PostgreSQL..."
            sudo systemctl start postgresql || ((ERROR_COUNT++))
            sudo systemctl enable postgresql || ((ERROR_COUNT++))
        fi
    fi
    
    # Redis
    if check_package_installed "redis-server"; then
        echo "✅ Redis já está instalado"
        if ! systemctl is-active --quiet redis-server; then
            echo "🔄 Iniciando serviço Redis..."
            sudo systemctl start redis-server || ((ERROR_COUNT++))
            sudo systemctl enable redis-server || ((ERROR_COUNT++))
        fi
    else
        echo "📦 Instalando Redis..."
        install_package "redis" || ((ERROR_COUNT++))
        if [ $ERROR_COUNT -eq 0 ]; then
            echo "🔄 Iniciando serviço Redis..."
            sudo systemctl start redis-server || ((ERROR_COUNT++))
            sudo systemctl enable redis-server || ((ERROR_COUNT++))
        fi
    fi
    
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Bancos de dados configurados com sucesso!"
    else
        echo "⚠️ Instalação concluída com $ERROR_COUNT erro(s)"
        return 1
    fi
}

install_chrome() {
    echo "� Verificando instalação do Google Chrome..."
    
    if check_package_installed "google-chrome-stable"; then
        echo "✅ Google Chrome já está instalado!"
        return 0
    fi
    
    echo "�📦 Instalando Google Chrome..."
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O chrome.deb || {
        echo "❌ Falha ao baixar Google Chrome"
        return 1
    }
    
    sudo apt install -y ./chrome.deb || {
        echo "❌ Falha ao instalar Google Chrome"
        rm chrome.deb
        return 1
    }
    
    rm chrome.deb
    
    if check_package_installed "google-chrome-stable"; then
        echo "✅ Google Chrome instalado com sucesso!"
        return 0
    else
        echo "❌ Falha na instalação do Google Chrome"
        return 1
    fi
}

install_vscode() {
    echo "� Verificando instalação do Visual Studio Code..."
    
    if check_package_installed "code"; then
        echo "✅ Visual Studio Code já está instalado!"
        return 0
    fi
    
    echo "�📦 Instalando Visual Studio Code..."
    
    # Adicionar chave e repositório
    if ! [ -f "/usr/share/keyrings/microsoft.gpg" ]; then
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg || {
            echo "❌ Falha ao baixar chave Microsoft"
            return 1
        }
        sudo install -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/ || {
            echo "❌ Falha ao instalar chave Microsoft"
            rm microsoft.gpg
            return 1
        }
        rm microsoft.gpg
    fi
    
    # Configurar repositório se não existir
    if ! [ -f "/etc/apt/sources.list.d/vscode.list" ]; then
        sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list' || {
            echo "❌ Falha ao configurar repositório VS Code"
            return 1
        }
        sudo apt update
    fi
    
    # Instalar VS Code
    sudo apt install -y code || {
        echo "❌ Falha ao instalar VS Code"
        return 1
    }
    
    if check_package_installed "code"; then
        echo "✅ Visual Studio Code instalado com sucesso!"
        return 0
    else
        echo "❌ Falha na instalação do VS Code"
        return 1
    fi
}

install_cursor() {
    echo "📦 Instalando Cursor AI..."
    local ERROR_COUNT=0
    local INSTALL_DIR="/usr/local/cursor"
    local BIN_DIR="/usr/local/bin"
    local APPLICATIONS_DIR="/usr/share/applications"
    local ICONS_DIR="/usr/share/icons/hicolor/512x512/apps"
    local BACKUP_DIR="/tmp/cursor_backup_$(date +%Y%m%d_%H%M%S)"
    local CURSOR_VERSION="1.1.3"
    local DOWNLOAD_URL="https://downloads.cursor.com/production/979ba33804ac150108481c14e0b5cb970bda3266/linux/x64/Cursor-${CURSOR_VERSION}-x86_64.AppImage"
    local ICON_URL="https://raw.githubusercontent.com/getcursor/cursor/main/packages/renderer/assets/cursor-512.png"

    # Verificar arquitetura do sistema
    if [ "$(uname -m)" != "x86_64" ]; then
        echo "❌ Este script suporta apenas sistemas x86_64"
        return 1
    fi

    # Verificar espaço em disco (mínimo 1GB livre)
    local FREE_SPACE=$(df -k /usr/local | awk 'NR==2 {print $4}')
    if [ "$FREE_SPACE" -lt 1048576 ]; then
        echo "❌ Espaço insuficiente em disco. Necessário pelo menos 1GB livre em /usr/local"
        return 1
    fi

    # Backup de instalação existente
    if [ -f "$BIN_DIR/cursor" ] || [ -d "$INSTALL_DIR" ]; then
        echo "📦 Fazendo backup da instalação existente..."
        mkdir -p "$BACKUP_DIR"
        [ -f "$BIN_DIR/cursor" ] && sudo cp "$BIN_DIR/cursor" "$BACKUP_DIR/"
        [ -d "$INSTALL_DIR" ] && sudo cp -r "$INSTALL_DIR" "$BACKUP_DIR/"
        [ -f "$APPLICATIONS_DIR/cursor.desktop" ] && sudo cp "$APPLICATIONS_DIR/cursor.desktop" "$BACKUP_DIR/"
        
        echo "🧹 Removendo instalação anterior..."
        sudo rm -f "$BIN_DIR/cursor"
        sudo rm -rf "$INSTALL_DIR"
        sudo rm -f "$APPLICATIONS_DIR/cursor.desktop"
        echo "✅ Backup salvo em: $BACKUP_DIR"
    fi

    echo "🔧 Criando diretórios de instalação..."
    sudo mkdir -p "$INSTALL_DIR" "$ICONS_DIR" || ((ERROR_COUNT++))
    sudo chown root:root "$INSTALL_DIR"
    sudo chmod 755 "$INSTALL_DIR"

    echo "⬇️ Baixando Cursor AppImage..."
    if ! sudo curl -L "$DOWNLOAD_URL" -o "$INSTALL_DIR/cursor.AppImage"; then
        echo "❌ Falha ao baixar o Cursor AppImage"
        ((ERROR_COUNT++))
    fi

    echo "⬇️ Baixando ícone do Cursor..."
    if ! sudo curl -L "$ICON_URL" -o "$ICONS_DIR/cursor.png"; then
        echo "❌ Falha ao baixar o ícone"
        ((ERROR_COUNT++))
    fi

    echo "🔒 Ajustando permissões..."
    sudo chmod +x "$INSTALL_DIR/cursor.AppImage" || ((ERROR_COUNT++))
    sudo chown root:root "$INSTALL_DIR/cursor.AppImage" || ((ERROR_COUNT++))

    echo "� Criando link simbólico..."
    sudo ln -sf "$INSTALL_DIR/cursor.AppImage" "$BIN_DIR/cursor" || ((ERROR_COUNT++))

    # Verificar e instalar dependências do AppImage
    echo "🔍 Verificando dependências..."
    if ! dpkg -s libfuse2 &>/dev/null && ! dpkg -s libfuse2:amd64 &>/dev/null; then
        echo "� Instalando libfuse2..."
        sudo apt update
        sudo apt install -y libfuse2 || ((ERROR_COUNT++))
    fi

    echo "�📝 Criando entrada no menu de aplicativos..."
    sudo tee "$APPLICATIONS_DIR/cursor.desktop" > /dev/null <<EOF || ((ERROR_COUNT++))
[Desktop Entry]
Name=Cursor
Comment=AI-first code editor
Exec=/usr/local/bin/cursor --no-sandbox
Icon=/usr/share/icons/hicolor/512x512/apps/cursor.png
Type=Application
Categories=Development;TextEditor;
Keywords=cursor;code;editor;ai;development;
StartupWMClass=Cursor
EOF

    # Atualizar cache de ícones e aplicativos
    echo "🔄 Atualizando cache do sistema..."
    sudo update-desktop-database "$APPLICATIONS_DIR" || ((ERROR_COUNT++))
    sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true

    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Cursor AI instalado com sucesso!"
        echo "ℹ️  Você pode iniciar o Cursor AI pelo menu de aplicativos ou executando 'cursor' no terminal"
        return 0
    else
        echo "❌ Instalação do Cursor AI concluída com $ERROR_COUNT erro(s)"
        return 1
    fi
}

install_postman() {
    local POSTMAN_DIR="/opt/postman"
    local DESKTOP_FILE="/usr/share/applications/postman.desktop"
    local BIN_LINK="/usr/local/bin/postman"
    
    echo "🔍 Verificando instalação do Postman..."
    
    # Verificação completa da instalação
    if [ -d "$POSTMAN_DIR" ] && [ -f "$DESKTOP_FILE" ] && [ -L "$BIN_LINK" ]; then
        if [ -x "$BIN_LINK" ] && "$BIN_LINK" --version &>/dev/null; then
            echo "✅ Postman já está instalado e funcionando!"
            return 0
        else
            echo "⚠️ Instalação do Postman encontrada mas pode estar corrompida, reinstalando..."
            sudo rm -rf "$POSTMAN_DIR" "$DESKTOP_FILE" "$BIN_LINK"
        fi
    fi
    
    echo "📦 Instalando Postman..."

    # Baixa e instala o Postman
    echo "⬇️ Baixando Postman..."
    wget -q -O /tmp/postman.tar.gz "https://dl.pstmn.io/download/latest/linux64" || {
        echo "❌ Falha ao baixar Postman"
        return 1
    }

    # Cria diretório e extrai
    sudo mkdir -p "$POSTMAN_DIR"
    sudo tar -xzf /tmp/postman.tar.gz -C "$POSTMAN_DIR" --strip-components=1
    rm /tmp/postman.tar.gz

    # Cria link simbólico
    sudo ln -sf "$POSTMAN_DIR/Postman" /usr/local/bin/postman

    # Cria atalho no menu
    echo "🔧 Criando atalho no menu..."
    sudo tee "$DESKTOP_FILE" > /dev/null <<EOF
[Desktop Entry]
Name=Postman
GenericName=API Development Environment
Comment=Build, test, and document your APIs
Exec=/usr/local/bin/postman
Terminal=false
Type=Application
Icon=$POSTMAN_DIR/app/resources/app/assets/icon.png
Categories=Development;Network;
EOF

    echo "✅ Postman instalado com sucesso!"
}

install_dev_tools() {
    echo "🛠️ Instalando ferramentas de desenvolvimento..."
    local ERROR_COUNT=0

    # Instalar Google Chrome
    install_chrome || ((ERROR_COUNT++))

    # Instalar VS Code
    install_vscode || ((ERROR_COUNT++))

    # Instalar Cursor
    install_cursor || ((ERROR_COUNT++))

    # Instalar Postman
    install_postman || ((ERROR_COUNT++))

    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Todas as ferramentas instaladas com sucesso!"
        return 0
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
alias update=\"sudo apt update\"
alias upgrade=\"sudo apt upgrade -y\"
alias install=\"sudo apt install -y\"

# PHP/Laravel
alias art=\"php artisan\"
alias arts=\"php artisan serve\"
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
    local ERROR_COUNT=0
    
    # Verificar instalação do MySQL
    if check_package_installed "mysql-server"; then
        echo "✅ MySQL Server já está instalado!"
    else
        echo "📦 Instalando MySQL Server..."
        install_package "mysql-server" || return 1
    fi
    
    # Verificar status do serviço
    if ! systemctl is-active --quiet mysql; then
        echo "🔄 Iniciando serviço MySQL..."
        sudo systemctl start mysql || ((ERROR_COUNT++))
    fi

 sudo systemctl enable mysql
 sudo systemctl start mysql

 echo "🔧 Criando banco de dados e usuário para desenvolvimento..."
 mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS laravel_dev;
CREATE USER IF NOT EXISTS 'dev'@'localhost' IDENTIFIED WITH mysql_native_password BY '';
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
    local ERROR_COUNT=0
    
    echo "� Verificando ambiente Laravel/Composer..."
    
    # Verificar Composer
    if command -v composer >/dev/null; then
        echo "✅ Composer já está instalado"
        # Verificar versão do Composer
        local COMPOSER_VERSION=$(composer --version | grep -oP 'Composer version \K[0-9]+\.[0-9]+')
        echo "ℹ️ Versão do Composer: $COMPOSER_VERSION"
        
        # Atualizar Composer se necessário
        if [ $(echo "$COMPOSER_VERSION < 2.0" | bc -l) -eq 1 ]; then
            echo "🔄 Atualizando Composer..."
            sudo composer self-update || ((ERROR_COUNT++))
        fi
    else
        echo "📦 Instalando Composer..."
        curl -sS https://getcomposer.org/installer | php$PHP_VERSION || ((ERROR_COUNT++))
        sudo mv composer.phar /usr/local/bin/composer || ((ERROR_COUNT++))
        sudo chmod +x /usr/local/bin/composer || ((ERROR_COUNT++))
    fi
    
    if [ $ERROR_COUNT -gt 0 ]; then
        echo "❌ Falha na configuração do Composer"
        return 1
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
    local ERROR_COUNT=0
    
    echo "� Verificando configuração do Supervisor..."
    
    # Verificar instalação e status do Supervisor
    if check_package_installed "supervisor"; then
        echo "✅ Supervisor já está instalado"
        if ! systemctl is-active --quiet supervisor; then
            echo "🔄 Iniciando serviço Supervisor..."
            sudo systemctl start supervisor || ((ERROR_COUNT++))
            sudo systemctl enable supervisor || ((ERROR_COUNT++))
        fi
    else
        echo "📦 Instalando Supervisor..."
        install_package "supervisor" || return 1
        
        echo "🔄 Iniciando serviço Supervisor..."
        sudo systemctl start supervisor || ((ERROR_COUNT++))
        sudo systemctl enable supervisor || ((ERROR_COUNT++))
    fi
    
    if [ $ERROR_COUNT -gt 0 ]; then
        echo "❌ Falha ao configurar serviço Supervisor"
        return 1
    fi

    # Configurar diretórios de projetos
    setup_project_directories "$USER" "${PROJETOS[@]}"
    
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

# Função para configurar diretórios de projetos
setup_project_directories() {
    local USER=$1
    local PROJETOS=("${@:2}")
    local BASE_DIR="/home/$USER/projects"
    local WWW_DIR="/var/www/projects"
    local ERROR_COUNT=0

    echo "📁 Configurando diretórios de projetos..."

    # Verificar se git está instalado
    if ! command -v git &> /dev/null; then
        echo "📦 Instalando Git..."
        sudo apt update && sudo apt install -y git || {
            echo "❌ Falha ao instalar Git"
            return 1
        }
    fi

    # Criar diretório base em /home/user/projects
    ensure_dir "$BASE_DIR"
    sudo chown -R $USER: "$BASE_DIR"

    # Criar diretório em /var/www/projects
    ensure_dir "$WWW_DIR"
    sudo chown -R $USER: "$WWW_DIR"

    # Criar diretórios para cada projeto e seus links simbólicos
    for PROJ in "${PROJETOS[@]}"; do
        local PROJ_DIR="$BASE_DIR/$PROJ"
        local WWW_PROJ_DIR="$WWW_DIR/$PROJ"
        local REPO_URL="${LARAVEL_PROJECTS[$PROJ]}"

        if [ -z "$REPO_URL" ]; then
            echo "⚠️ URL do repositório não configurada para $PROJ"
            continue
        fi

        # Clonar ou atualizar o projeto
        clone_or_update_project "$PROJ" "$REPO_URL" "$PROJ_DIR" || {
            ((ERROR_COUNT++))
            continue
        }

        # Criar link simbólico se não existir
        if [ ! -L "$WWW_PROJ_DIR" ]; then
            echo "🔗 Criando link simbólico para $PROJ..."
            sudo ln -s "$PROJ_DIR" "$WWW_PROJ_DIR" || ((ERROR_COUNT++))
        fi
    done

    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Diretórios de projetos configurados com sucesso!"
        return 0
    else
        echo "⚠️ Configuração concluída com $ERROR_COUNT erro(s)"
        return 1
    fi
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

# Configuração dos projetos Laravel
declare -A LARAVEL_PROJECTS=(
    ["gym-management-system"]="git@github.com:marcelobogas/gym-management-system.git"
    ["school-management-system"]="git@github.com:marcelobogas/school-management-system.git"
    ["api"]="git@github.com:marcelobogas/api.git"
)

# Função para clonar ou atualizar projetos
clone_or_update_project() {
    local PROJECT_NAME=$1
    local REPO_URL=$2
    local PROJECT_DIR=$3
    
    if [ ! -d "$PROJECT_DIR/.git" ]; then
        echo "📥 Clonando $PROJECT_NAME..."
        git clone "$REPO_URL" "$PROJECT_DIR" || {
            echo "❌ Falha ao clonar $PROJECT_NAME"
            return 1
        }
    else
        echo "🔄 Atualizando $PROJECT_NAME..."
        (cd "$PROJECT_DIR" && git pull) || {
            echo "⚠️ Falha ao atualizar $PROJECT_NAME"
            return 1
        }
    fi
    
    # Verificar se é um projeto Laravel e instalar dependências
    if [ -f "$PROJECT_DIR/composer.json" ]; then
        echo "🔧 Instalando dependências do $PROJECT_NAME..."
        (cd "$PROJECT_DIR" && composer install --no-interaction) || {
            echo "⚠️ Falha ao instalar dependências do $PROJECT_NAME"
            return 1
        }
        
        # Configurar .env se não existir
        if [ ! -f "$PROJECT_DIR/.env" ] && [ -f "$PROJECT_DIR/.env.example" ]; then
            cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
            (cd "$PROJECT_DIR" && php artisan key:generate) || true
        fi
    fi
    
    return 0
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

# Função auxiliar para verificar se um pacote está instalado
check_package_installed() {
    local package="$1"
    if dpkg -s "$package" &>/dev/null; then
        return 0
    fi
    return 1
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
