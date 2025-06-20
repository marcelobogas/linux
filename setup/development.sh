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
        "php$PHP_VERSION-zip"
        "php$PHP_VERSION-mysql"
        "php$PHP_VERSION-pgsql"
        "php$PHP_VERSION-curl"
        "php$PHP_VERSION-xdebug"
        "php$PHP_VERSION-redis"
        "php$PHP_VERSION-gd"
        "php$PHP_VERSION-bcmath"
        "php$PHP_VERSION-intl"
        "php$PHP_VERSION-fpm"
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

configure_dev_aliases() {
    local ALIASES_FILE="/home/$USER/.bash_aliases"
    local ALIASES_CONTENT="# Package Management
alias update=\"sudo nala update\"
alias upgrade=\"sudo nala upgrade -y\"
alias nalai=\"sudo nala install -y\"

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

# NVM Configuration
export NVM_DIR=\"\$([ -z \"\${XDG_CONFIG_HOME-}\" ] && printf %s \"\${HOME}/.nvm\" || printf %s \"\${XDG_CONFIG_HOME}/nvm\")\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\" # This loads nvm"

    echo "🔍 Verificando arquivo de aliases..."
    
    if [ -f "$ALIASES_FILE" ]; then
        echo "📝 Arquivo .bash_aliases encontrado, verificando conteúdo..."
        
        # Criar backup do arquivo existente
        cp "$ALIASES_FILE" "${ALIASES_FILE}.bak"
        echo "📦 Backup criado: ${ALIASES_FILE}.bak"
        
        # Verificar cada alias
        local MISSING_ALIASES=0
        local ALIASES_TO_CHECK=(
            "alias update="
            "alias upgrade="
            "alias nalai="
            "alias art="
            "alias arts
            ="
            "alias ni="
            "alias nu="
            "alias nrd="
            "alias nrb="
            "alias ci="
            "alias cu="
            "alias cr="
            "alias cda="
            "alias sail="
        )
        
        for alias in "${ALIASES_TO_CHECK[@]}"; do
            if ! grep -q "^$alias" "$ALIASES_FILE"; then
                ((MISSING_ALIASES++))
            fi
        done
        
        if [ $MISSING_ALIASES -gt 0 ]; then
            echo "⚠️ Alguns aliases estão faltando, atualizando arquivo..."
            echo "$ALIASES_CONTENT" > "$ALIASES_FILE"
            echo "✅ Aliases atualizados com sucesso!"
        else
            echo "✅ Todos os aliases já estão configurados!"
        fi
    else
        echo "📝 Criando novo arquivo .bash_aliases..."
        echo "$ALIASES_CONTENT" > "$ALIASES_FILE"
        echo "✅ Arquivo .bash_aliases criado com sucesso!"
    fi
    
    # Garantir que os arquivos RC carregam os aliases
    # Para Bash
    if ! grep -q "\.bash_aliases" "$HOME/.bashrc"; then
        echo -e "\n# Alias definitions\nif [ -f ~/.bash_aliases ]; then\n    . ~/.bash_aliases\nfi" >> "$HOME/.bashrc"
        echo "✅ Configuração adicionada ao .bashrc"
    fi
    
    # Para Zsh
    if [ -f "$HOME/.zshrc" ]; then
        echo "🔍 Verificando configurações do Zsh..."
        if ! grep -q "if \[ -f ~/\.bash_aliases \]; then" "$HOME/.zshrc"; then
            # Criar backup do .zshrc
            cp "$HOME/.zshrc" "$HOME/.zshrc.bak"
            echo "📦 Backup do .zshrc criado: $HOME/.zshrc.bak"
            
            # Adicionar configuração
            echo -e "\n# Alias definitions\nif [ -f ~/.bash_aliases ]; then\n    . ~/.bash_aliases\nfi" >> "$HOME/.zshrc"
            echo "✅ Configuração de aliases adicionada ao .zshrc"
        else
            echo "✅ .zshrc já está configurado para carregar os aliases"
        fi
    fi
    
    # Recarregar configurações do shell
    echo "🔄 Recarregando configurações do shell..."
    
    # Recarregar .bashrc
    source "$HOME/.bashrc" 2>/dev/null || true
    
    # Recarregar .zshrc se existir
    if [ -f "$HOME/.zshrc" ]; then
        if [ "$SHELL" = "/usr/bin/zsh" ] || [ "$SHELL" = "/bin/zsh" ]; then
            source "$HOME/.zshrc" 2>/dev/null || true
            echo "✅ Configurações do Zsh atualizadas"
        else
            echo "ℹ️  Arquivo .zshrc encontrado, mas você não está usando Zsh"
            echo "   Para carregar as configurações, execute: source ~/.zshrc"
        fi
    fi
    
    echo "✅ Configurações de shell atualizadas com sucesso!"
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

# Configuração do ambiente de desenvolvimento completo
setup_dev_environment() {
    echo "🚀 Iniciando configuração completa do ambiente de desenvolvimento..."
    local ERROR_COUNT=0

    # Configurar aliases primeiro para ter disponível durante o resto da instalação
    configure_dev_aliases || ((ERROR_COUNT++))

    # Configurar PHP e servidor web
    setup_php_environment || ((ERROR_COUNT++))
    setup_web_server || ((ERROR_COUNT++))

    # Configurar Node.js
    setup_node_environment || ((ERROR_COUNT++))

    # Configurar bancos de dados
    setup_databases || ((ERROR_COUNT++))

    # Instalar ferramentas de desenvolvimento
    install_dev_tools || ((ERROR_COUNT++))

    # Verificar resultado final
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Ambiente de desenvolvimento configurado com sucesso!"
        return 0
    else
        echo "⚠️ Configuração concluída com $ERROR_COUNT erro(s)"
        echo "📋 Por favor, verifique as mensagens acima"
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
    echo -e "${GREEN}7)${NC} Configurar TUDO"
    echo -e "${GREEN}0)${NC} Voltar"
    
    read -r choice
    case $choice in
        1) configure_dev_aliases ;;
        2) setup_php_environment ;;
        3) setup_web_server ;;
        4) setup_node_environment ;;
        5) setup_databases ;;
        6) install_dev_tools ;;
        7) setup_dev_environment ;;
        0) return ;;
        *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
}

# Execução principal
check_root
show_dev_menu
