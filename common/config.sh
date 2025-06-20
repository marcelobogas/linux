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
