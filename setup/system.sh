#!/usr/bin/bash

source "$(dirname "$0")/../common/functions.sh"
source "$(dirname "$0")/../common/config.sh"

setup_system_base() {
    echo "🚀 Configurando sistema base..."
    
    # Nala
    if ! command -v nala &> /dev/null; then
        sudo apt update
        sudo apt install nala -y
    fi
    
    # Pacotes essenciais
    for pkg in "${ESSENTIAL_PACKAGES[@]}"; do
        install_package "$pkg"
    done
    
    # Flatpak
    echo "📦 Configurando Flatpak..."
    if ! flatpak remote-list | grep -q flathub; then
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
    install_package "gnome-software-plugin-flatpak"
    
    # Flatseal
    if ! flatpak list | grep -q com.github.tchx84.Flatseal; then
        flatpak install -y flathub com.github.tchx84.Flatseal
    fi
}

setup_system_tools() {
    echo "🔧 Instalando ferramentas do sistema..."
    
    # Grub Customizer
    if ! dpkg -s grub-customizer &>/dev/null; then
        install_deb "https://launchpadlibrarian.net/570407966/grub-customizer_5.1.0-3build1_amd64.deb" "grub-customizer"
    fi
    
    # Boot Repair
    if ! command -v boot-repair > /dev/null; then
        add_ppa "yannubuntu/boot-repair"
        install_package "boot-repair"
    fi
}

setup_sudo() {
    echo "🔐 Configurando sudo..."
    local SUDOERS_LINE="${USER_NAME} ALL=(ALL) NOPASSWD: ALL"
    
    if ! sudo grep -Fxq "$SUDOERS_LINE" /etc/sudoers; then
        echo "$SUDOERS_LINE" | sudo EDITOR='tee -a' visudo > /dev/null
    fi
}

# Menu do sistema
show_system_menu() {
    echo -e "\n${BLUE}Escolha o que deseja configurar:${NC}"
    echo -e "${GREEN}1)${NC} Sistema base e pacotes essenciais"
    echo -e "${GREEN}2)${NC} Ferramentas do sistema"
    echo -e "${GREEN}3)${NC} Configurar sudo sem senha"
    echo -e "${GREEN}4)${NC} Tudo acima"
    echo -e "${GREEN}0)${NC} Voltar"
    
    read -r choice
    case $choice in
        1) setup_system_base ;;
        2) setup_system_tools ;;
        3) setup_sudo ;;
        4)
            setup_system_base
            setup_system_tools
            setup_sudo
            ;;
        0) return ;;
        *) echo "Opção inválida" ;;
    esac
}

# Execução principal
check_root
show_system_menu
