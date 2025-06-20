#!/usr/bin/bash

source "$(dirname "$0")/../common/functions.sh"
source "$(dirname "$0")/../common/config.sh"

setup_gnome_theme() {
    echo "🎨 Configurando tema do GNOME..."
    
    # Dock
    gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize'
    
    # Outras configurações do GNOME podem ser adicionadas aqui
}

setup_terminal() {
    echo "⌨️ Configurando terminal..."
    
    # Instalar ZSH se necessário
    install_package "zsh"
    
    # Oh My Zsh
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    
    # Configurar como shell padrão
    if [ "$SHELL" != "/usr/bin/zsh" ]; then
        chsh -s $(which zsh)
    fi
}

# Menu de tema
show_theme_menu() {
    echo -e "\n${BLUE}Escolha o que deseja configurar:${NC}"
    echo -e "${GREEN}1)${NC} Tema do GNOME"
    echo -e "${GREEN}2)${NC} Terminal"
    echo -e "${GREEN}3)${NC} Tudo acima"
    echo -e "${GREEN}0)${NC} Voltar"
    
    read -r choice
    case $choice in
        1) setup_gnome_theme ;;
        2) setup_terminal ;;
        3)
            setup_gnome_theme
            setup_terminal
            ;;
        0) return ;;
        *) echo "Opção inválida" ;;
    esac
}

# Execução principal
check_root
show_theme_menu
