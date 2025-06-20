#!/usr/bin/bash

source "$(dirname "$0")/../common/functions.sh"
source "$(dirname "$0")/../common/config.sh"

setup_gnome_theme() {
    echo "🎨 Configurando tema do GNOME..."
    local ERROR_COUNT=0
    
    # Dock
    gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize'
    
    # Instalar git e dependências necessárias
    if ! command -v git &> /dev/null; then
        echo "📦 Instalando git..."
        install_package "git" || ((ERROR_COUNT++))
    else
        echo "✅ Git já está instalado!"
    fi

    # Instalar Evolve Theme Manager
    echo "📦 Instalando Evolve Theme Manager..."
    if ! command -v evolve-themes &> /dev/null; then
        local EVOLVE_DIR="/tmp/evolve-themes"
        
        # Clonar o repositório
        if [ ! -d "$EVOLVE_DIR" ]; then
            echo "🔄 Clonando repositório Evolve Theme Manager..."
            git clone https://github.com/telage/evolve-themes.git "$EVOLVE_DIR" || ((ERROR_COUNT++))
        fi
        
        # Instalar dependências
        echo "📦 Instalando dependências do Evolve..."
        install_package "gir1.2-gtk-3.0" || ((ERROR_COUNT++))
        install_package "python3-gi" || ((ERROR_COUNT++))
        install_package "python3-pip" || ((ERROR_COUNT++))
        
        # Instalar Evolve
        if [ -d "$EVOLVE_DIR" ]; then
            cd "$EVOLVE_DIR" || return 1
            sudo pip3 install . || ((ERROR_COUNT++))
            cd "$HOME" || return 1
            rm -rf "$EVOLVE_DIR"
            echo "✅ Evolve Theme Manager instalado!"
        else
            echo "❌ Falha ao instalar Evolve Theme Manager"
            ((ERROR_COUNT++))
        fi
    else
        echo "✅ Evolve Theme Manager já está instalado!"
    fi

    # Instalar dependências de temas
    echo "📦 Instalando dependências dos temas..."
    install_package "gtk2-engines-murrine" || ((ERROR_COUNT++))
    install_package "gtk2-engines-pixbuf" || ((ERROR_COUNT++))
    install_package "gnome-tweaks" || ((ERROR_COUNT++))

    # Instalar tema de ícones Tela
    if [ ! -d "$HOME/.icons/Tela" ]; then
        echo "📦 Instalando tema de ícones Tela..."
        mkdir -p "$HOME/.icons"
        cd "$HOME/.icons" || return 1
        
        if [ ! -d "$HOME/.icons/Tela-icon-theme" ]; then
            echo "🔄 Clonando repositório Tela-icon-theme..."
            git clone https://github.com/vinceliuice/Tela-icon-theme.git || ((ERROR_COUNT++))
        fi
        
        cd "Tela-icon-theme" || return 1
        ./install.sh || ((ERROR_COUNT++))
        cd "$HOME" || return 1
        echo "✅ Tema de ícones Tela instalado!"
    else
        echo "✅ Tema de ícones Tela já está instalado!"
    fi

    # Instalar tema de ícones Papirus
    if ! dpkg -l | grep -q papirus-icon-theme; then
        echo "📦 Instalando tema de ícones Papirus..."
        
        # Adicionar repositório Papirus
        if ! grep -q "^deb.*papirus" /etc/apt/sources.list.d/*.list 2>/dev/null; then
            echo "🔄 Adicionando repositório Papirus..."
            sudo add-apt-repository -y ppa:papirus/papirus || ((ERROR_COUNT++))
            sudo apt update || ((ERROR_COUNT++))
        fi
        
        # Instalar tema
        install_package "papirus-icon-theme" || ((ERROR_COUNT++))
        echo "✅ Tema de ícones Papirus instalado!"
    else
        echo "✅ Tema de ícones Papirus já está instalado!"
    fi

    # Instalar Everforest GTK Theme
    if [ ! -d "$HOME/.themes/Everforest-Dark-BL" ]; then
        echo "📦 Instalando tema Everforest GTK..."
        local EVERFOREST_DIR="/tmp/Everforest-GTK-Theme"
        
        # Clonar o repositório
        if [ ! -d "$EVERFOREST_DIR" ]; then
            echo "🔄 Clonando repositório Everforest GTK Theme..."
            git clone https://github.com/Fausto-Korpsvart/Everforest-GTK-Theme.git "$EVERFOREST_DIR" || ((ERROR_COUNT++))
        fi
        
        # Copiar temas
        echo "📦 Instalando temas Everforest..."
        mkdir -p "$HOME/.themes"
        cp -r "$EVERFOREST_DIR/themes/Everforest"* "$HOME/.themes/" || ((ERROR_COUNT++))
        
        # Copiar ícones
        echo "📦 Instalando ícones Everforest..."
        mkdir -p "$HOME/.icons"
        cp -r "$EVERFOREST_DIR/icons/Everforest"* "$HOME/.icons/" || ((ERROR_COUNT++))
        
        # Configurar Flatpak para usar temas
        echo "🔧 Configurando Flatpak para usar temas personalizados..."
        flatpak override --user --filesystem=~/.themes || ((ERROR_COUNT++))
        flatpak override --user --filesystem=~/.icons || ((ERROR_COUNT++))
        
        # Limpar diretório temporário
        rm -rf "$EVERFOREST_DIR"
        echo "✅ Tema Everforest instalado!"
    else
        echo "✅ Tema Everforest já está instalado!"
    fi

    # Aplicar temas
    gsettings set org.gnome.desktop.interface gtk-theme 'Everforest-Dark-BL'
    gsettings set org.gnome.desktop.interface icon-theme 'Tela'
    
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Temas do GNOME configurados com sucesso!"
        echo "ℹ️  Você pode gerenciar seus temas usando:"
        echo "   1. Evolve Theme Manager (comando: evolve-themes)"
        echo "   2. Configurações do GNOME:"
        echo "      - GTK Theme: Everforest (várias variações disponíveis)"
        echo "      - Ícones: Tela, Everforest ou Papirus"
    else
        echo "⚠️ Configuração concluída com $ERROR_COUNT erro(s)"
        return 1
    fi
}

setup_terminal() {
    echo "⌨️ Configurando terminal..."
    local ERROR_COUNT=0
    
    # Instalar ZSH se necessário
    if command -v zsh > /dev/null; then
        echo "✅ ZSH já está instalado!"
    else
        echo "📦 Instalando ZSH..."
        install_package "zsh" || ((ERROR_COUNT++))
    fi
    
    # Oh My Zsh
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "✅ Oh My Zsh já está instalado!"
    else
        echo "📦 Instalando Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || ((ERROR_COUNT++))
    fi
    
    # Powerlevel10k
    local P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [ -d "$P10K_DIR" ]; then
        echo "✅ Powerlevel10k já está instalado!"
    else
        echo "📦 Instalando Powerlevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" || ((ERROR_COUNT++))
    fi
    
    # Instalar plugins do ZSH
    echo "🔧 Configurando plugins do ZSH..."
    setup_zsh_plugins || ((ERROR_COUNT++))
    
    # Configurar .zshrc
    if [ -f "$HOME/.zshrc" ]; then
        echo "🔧 Configurando .zshrc..."
        # Fazer backup do .zshrc
        cp "$HOME/.zshrc" "$HOME/.zshrc.bak"
        echo "📦 Backup criado: $HOME/.zshrc.bak"
        
        # Configurar tema
        if ! grep -q "^ZSH_THEME=\"powerlevel10k/powerlevel10k\"" "$HOME/.zshrc"; then
            echo "🔧 Configurando Powerlevel10k como tema padrão..."
            sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
        fi
        
        # Configurar plugins
        if ! grep -q "^plugins=(.*zsh-autosuggestions.*zsh-syntax-highlighting.*)" "$HOME/.zshrc"; then
            echo "🔧 Configurando plugins ZSH..."
            sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting copypath copyfile copybuffer jsontools)/' "$HOME/.zshrc"
        fi
        
        echo "✅ Configurações do .zshrc atualizadas!"
    fi
    
    # Configurar fontes
    local FONT_DIR="$HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"

    # MesloLGS NF (para Powerlevel10k)
    if [ ! -f "$FONT_DIR/MesloLGS NF Regular.ttf" ]; then
        echo "📦 Instalando fontes MesloLGS NF..."
        wget -P "$FONT_DIR" https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf
        wget -P "$FONT_DIR" https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf
        wget -P "$FONT_DIR" https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf
        wget -P "$FONT_DIR" https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf
        echo "✅ Fontes MesloLGS NF instaladas!"
    else
        echo "✅ Fontes MesloLGS NF já estão instaladas!"
    fi

    # Fira Code Nerd Font
    if [ ! -f "$FONT_DIR/Fira Code Regular Nerd Font Complete.ttf" ]; then
        echo "📦 Instalando Fira Code Nerd Font..."
        local FIRA_ZIP="/tmp/FiraCode.zip"
        wget -O "$FIRA_ZIP" https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/FiraCode.zip
        unzip -o "$FIRA_ZIP" -d "$FONT_DIR" '*.ttf'
        rm "$FIRA_ZIP"
        echo "✅ Fira Code Nerd Font instalada!"
    else
        echo "✅ Fira Code Nerd Font já está instalada!"
    fi

    # Atualizar cache de fontes
    echo "🔄 Atualizando cache de fontes..."
    fc-cache -f -v
    
    # Configurar como shell padrão
    if [ "$SHELL" != "/usr/bin/zsh" ]; then
        echo "🔧 Configurando ZSH como shell padrão..."
        chsh -s $(which zsh)
    fi
    
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Terminal configurado com sucesso!"
        echo "ℹ️  Para configurar o Powerlevel10k, execute 'p10k configure' após reiniciar o terminal"
        echo "ℹ️  Fontes instaladas:"
        echo "   - MesloLGS NF (recomendada para Powerlevel10k)"
        echo "   - Fira Code Nerd Font (ótima para programação)"
        echo "   Configure sua preferência no terminal e editor de código"
    else
        echo "⚠️ Configuração concluída com $ERROR_COUNT erro(s)"
        return 1
    fi
}

setup_zsh_plugins() {
    local ERROR_COUNT=0
    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    
    # zsh-autosuggestions
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
        echo "📦 Instalando plugin zsh-autosuggestions..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" || ((ERROR_COUNT++))
    else
        echo "✅ Plugin zsh-autosuggestions já está instalado!"
    fi
    
    # zsh-syntax-highlighting
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
        echo "📦 Instalando plugin zsh-syntax-highlighting..."
        git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" || ((ERROR_COUNT++))
    else
        echo "✅ Plugin zsh-syntax-highlighting já está instalado!"
    fi
    
    return $ERROR_COUNT
}

setup_homebrew_theme() {
    echo "🎨 Configurando tema Homebrew..."
    
    # Verificar se Oh My Zsh está instalado
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo "❌ Oh My Zsh precisa estar instalado primeiro!"
        return 1
    fi
    
    # Download do tema Homebrew
    local THEME_PATH="$HOME/.oh-my-zsh/custom/themes"
    mkdir -p "$THEME_PATH"
    
    if [ ! -f "$THEME_PATH/homebrew.zsh-theme" ]; then
        echo "📦 Baixando tema Homebrew..."
        wget -O "$THEME_PATH/homebrew.zsh-theme" https://raw.githubusercontent.com/maximbaz/homebrew-zsh-theme/master/homebrew.zsh-theme || {
            echo "❌ Falha ao baixar o tema Homebrew"
            return 1
        }
        echo "✅ Tema Homebrew baixado com sucesso!"
    else
        echo "✅ Tema Homebrew já está instalado!"
    fi
    
    # Verificar se o tema já está configurado
    if grep -q '^ZSH_THEME="homebrew"' "$HOME/.zshrc"; then
        echo "✅ Tema Homebrew já está configurado!"
        return 0
    fi
    
    # Fazer backup do .zshrc
    if [ -f "$HOME/.zshrc" ]; then
        cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d_%H%M%S)"
        echo "📦 Backup do .zshrc criado"
    fi
    
    # Configurar tema
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="homebrew"/' "$HOME/.zshrc"
    
    echo "✅ Tema Homebrew configurado com sucesso!"
    echo "ℹ️  Para aplicar as alterações, reinicie o terminal ou execute: source ~/.zshrc"
}

# Menu de tema
show_theme_menu() {
    echo -e "\n${BLUE}Escolha o que deseja configurar:${NC}"
    echo -e "${GREEN}1)${NC} Tema do GNOME"
    echo -e "${GREEN}2)${NC} Terminal com Powerlevel10k"
    echo -e "${GREEN}3)${NC} Terminal com tema Homebrew"
    echo -e "${GREEN}4)${NC} Tudo acima (usando Powerlevel10k)"
    echo -e "${GREEN}0)${NC} Voltar"
    
    read -r choice
    case $choice in
        1) setup_gnome_theme ;;
        2) setup_terminal ;;  # Terminal com Powerlevel10k
        3) 
            setup_terminal
            setup_homebrew_theme
            ;;
        4)
            setup_gnome_theme
            setup_terminal
            ;;
        0) return ;;
        *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
}

# Execução principal
check_root
show_theme_menu
