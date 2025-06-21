#!/usr/bin/bash

# Cores para o terminal
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export YELLOW='\033[1;33m'
export NC='\033[0m' # No Color
export BOLD='\033[1m'

# Diretórios comuns
export USER_NAME=$(whoami)
export HOME_DIR="/home/$USER_NAME"
export APPS_DIR="$HOME_DIR/Applications"
export PROJECTS_DIR="$HOME_DIR/projects"

# URLs de download
export CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
export VSCODE_URL="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
export CURSOR_URL="https://downloads.cursor.com/production/53b99ce608cba35127ae3a050c1738a959750865/linux/x64/Cursor-1.0.0-x86_64.AppImage"

# Função para exibir mensagens com cores
log_info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# Verificar root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        log_error "Por favor, não execute este script como root"
        exit 1
    fi
}

# Pacotes essenciais
ESSENTIAL_PACKAGES=(
    gnome-tweaks
    gnome-shell-extension-manager
    ca-certificates
    ubuntu-restricted-extras
    build-essential
    synaptic
    wrk
    snapd
    gparted
    preload
    vsftpd
    filezilla
    neofetch
    vlc
    gimp
    redis
    supervisor
    timeshift
    numlockx
    net-tools
    vim
    gdebi
    git
    curl
    apache2
    tree
    gnupg
    dirmngr
    gcc
    g++
    make
    flatpak
    sassc
)

# Configurações padrão
readonly DEFAULT_PHP_VERSION="8.4"
readonly DEFAULT_NODE_VERSION="22"
readonly REQUIRED_DISK_SPACE=5120  # 5GB em MB
readonly MIN_RAM=4096  # 4GB em MB

# Validar ambiente
validate_environment() {
    local ERROR_COUNT=0
    
    log_info "Iniciando validação do ambiente..."
    
    # Verificar pacotes essenciais críticos
    local CRITICAL_PACKAGES=("apt" "dpkg" "flatpak" "git" "curl")
    for pkg in "${CRITICAL_PACKAGES[@]}"; do
        if ! check_package_installed "$pkg"; then
            log_error "Pacote crítico $pkg não está instalado"
            ((ERROR_COUNT++))
        fi
    done
    
    # Verificar repositório universe
    if ! check_universe_repository; then
        log_error "Falha ao configurar repositório Universe"
        ((ERROR_COUNT++))
    fi
    
    # Verificar espaço em disco
    if ! check_disk_space "/usr/local" "$REQUIRED_DISK_SPACE"; then
        log_error "Espaço em disco insuficiente"
        ((ERROR_COUNT++))
    fi
    
    # Verificar memória RAM
    local TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt "$MIN_RAM" ]; then
        log_warning "Memória RAM abaixo do recomendado (${MIN_RAM}MB). Disponível: ${TOTAL_RAM}MB"
    fi
    
    # Verificar conexão com a internet
    if ! ping -c 1 google.com &>/dev/null; then
        log_error "Sem conexão com a internet"
        ((ERROR_COUNT++))
    fi
    
    # Verificar arquitetura do sistema
    if [ "$(uname -m)" != "x86_64" ]; then
        log_error "Este script suporta apenas sistemas x86_64"
        ((ERROR_COUNT++))
    fi
    
    return $ERROR_COUNT
}

# Variáveis de versão
declare -A VERSIONS
VERSIONS=(
    ["php"]="$DEFAULT_PHP_VERSION"
    ["node"]="$DEFAULT_NODE_VERSION"
    ["mysql"]="8.0"
    ["postgresql"]="16"
)

# Configurações de diretórios
declare -A DIR_CONFIG
DIR_CONFIG=(
    ["temp"]="/tmp/linux_setup"
    ["backups"]="/tmp/linux_setup/backups"
    ["downloads"]="/tmp/linux_setup/downloads"
    ["logs"]="/tmp/linux_setup/logs"
)

# Criar diretórios necessários
setup_directories() {
    for dir in "${DIR_CONFIG[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
        fi
    done
}

# Inicialização do ambiente
init_environment() {
    setup_directories
    if ! validate_environment; then
        log_error "Falha na validação do ambiente"
        return 1
    fi
    log_success "Ambiente validado com sucesso"
    return 0
}

# Executar inicialização
init_environment || exit 1
