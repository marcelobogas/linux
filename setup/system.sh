#!/usr/bin/bash

source "$(dirname "$0")/../common/functions.sh"
source "$(dirname "$0")/../common/config.sh"

# Função auxiliar para verificar espaço em disco
check_disk_space() {
    local path="$1"
    local required_mb="$2"
    local available_kb=$(df -k "$path" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        echo "❌ Espaço insuficiente em $path. Disponível: ${available_mb}MB, Necessário: ${required_mb}MB"
        return 1
    fi
    echo "✅ Espaço suficiente em $path (${available_mb}MB disponível)"
    return 0
}

setup_system_base() {
    echo "🚀 Configurando sistema base..."
    local ERROR_COUNT=0
    local MISSING_PACKAGES=()
    
    # Verificar repositórios e atualizações
    echo "� Verificando atualizações do sistema..."
    if ! sudo apt update; then
        echo "⚠️ Falha ao atualizar repositórios"
        ((ERROR_COUNT++))
    else
        # Verificar se há atualizações pendentes
        if [ $(apt list --upgradable 2>/dev/null | wc -l) -gt 1 ]; then
            echo "🔄 Instalando atualizações do sistema..."
            sudo apt upgrade -y || ((ERROR_COUNT++))
        else
            echo "✅ Sistema está atualizado"
        fi
    fi
    
    # Verificar pacotes essenciais
    echo "� Verificando pacotes essenciais..."
    for pkg in "${ESSENTIAL_PACKAGES[@]}"; do
        if ! check_package_installed "$pkg"; then
            MISSING_PACKAGES+=("$pkg")
        else
            echo "✅ Pacote $pkg já está instalado"
        fi
    done
    
    # Instalar pacotes faltantes
    if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
        echo "📦 Instalando pacotes faltantes: ${MISSING_PACKAGES[*]}"
        for pkg in "${MISSING_PACKAGES[@]}"; do
            install_package "$pkg" || ((ERROR_COUNT++))
        done
    fi
    
    # Flatpak
    echo "📦 Configurando Flatpak..."
    if ! flatpak remote-list | grep -q flathub; then
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || ((ERROR_COUNT++))
    fi
    install_package "gnome-software-plugin-flatpak" || ((ERROR_COUNT++))
    
    # Flatseal
    if ! flatpak list | grep -q com.github.tchx84.Flatseal; then
        echo "📦 Instalando Flatseal..."
        flatpak install -y flathub com.github.tchx84.Flatseal || ((ERROR_COUNT++))
    fi
    
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Sistema base configurado com sucesso!"
    else
        echo "⚠️ Configuração concluída com $ERROR_COUNT erro(s)"
        return 1
    fi
}

setup_system_tools() {
    echo "🔧 Verificando ferramentas do sistema..."
    local ERROR_COUNT=0
    
    # Grub Customizer
    if check_package_installed "grub-customizer"; then
        echo "✅ Grub Customizer já está instalado"
        # Verificar versão instalada
        local INSTALLED_VERSION=$(dpkg -s grub-customizer | grep Version | cut -d' ' -f2)
        local REQUIRED_VERSION="5.1.0"
        
        if dpkg --compare-versions "$INSTALLED_VERSION" lt "$REQUIRED_VERSION"; then
            echo "� Atualizando Grub Customizer para versão $REQUIRED_VERSION..."
            install_deb "https://launchpadlibrarian.net/570407966/grub-customizer_5.1.0-3build1_amd64.deb" "grub-customizer" || ((ERROR_COUNT++))
        fi
    else
        echo "📦 Instalando Grub Customizer..."
        install_deb "https://launchpadlibrarian.net/570407966/grub-customizer_5.1.0-3build1_amd64.deb" "grub-customizer" || ((ERROR_COUNT++))
    fi
    
    # Boot Repair
    if check_package_installed "boot-repair"; then
        echo "✅ Boot Repair já está instalado"
    else
        echo "📦 Instalando Boot Repair..."
        # Verificar se o PPA já existe
        if ! grep -r "yannubuntu/boot-repair" /etc/apt/ &>/dev/null; then
            add_ppa "yannubuntu/boot-repair" || ((ERROR_COUNT++))
        fi
        install_package "boot-repair" || ((ERROR_COUNT++))
    fi
    
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Ferramentas do sistema instaladas com sucesso!"
    else
        echo "⚠️ Instalação concluída com $ERROR_COUNT erro(s)"
        return 1
    fi
}

setup_sudo() {
    echo "🔐 Configurando permissões sudo..."
    local ERROR_COUNT=0
    local SUDOERS_LINE="${USER_NAME} ALL=(ALL) NOPASSWD: ALL"
    local SUDOERS_FILE="/etc/sudoers"
    local SUDOERS_TMP="/tmp/sudoers.tmp"
    
    echo "🔍 Verificando configuração sudo..."
    
    # Verificar se o usuário existe
    if ! id "$USER_NAME" &>/dev/null; then
        echo "❌ Usuário $USER_NAME não existe"
        return 1
    fi
    
    # Verificar se o usuário já está no grupo sudo
    if ! groups "$USER_NAME" | grep -q '\bsudo\b'; then
        echo "🔧 Adicionando $USER_NAME ao grupo sudo..."
        sudo usermod -aG sudo "$USER_NAME" || ((ERROR_COUNT++))
    else
        echo "✅ Usuário já está no grupo sudo"
    fi
    
    # Verificar entrada no sudoers
    if sudo grep -Fxq "$SUDOERS_LINE" "$SUDOERS_FILE"; then
        echo "✅ Configuração sudo já existe"
    else
        echo "🔧 Adicionando configuração sudo..."
        # Validar sintaxe antes de aplicar
        echo "$SUDOERS_LINE" | sudo EDITOR='tee -a' visudo -f "$SUDOERS_TMP" > /dev/null || {
            echo "❌ Erro de sintaxe na configuração sudo"
            ((ERROR_COUNT++))
            return 1
        }
        
        # Aplicar mudança
        sudo cp "$SUDOERS_FILE" "${SUDOERS_FILE}.bak"
        echo "$SUDOERS_LINE" | sudo EDITOR='tee -a' visudo > /dev/null || ((ERROR_COUNT++))
    fi
    
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Permissões sudo configuradas com sucesso!"
        return 0
    else
        echo "❌ Falha ao configurar permissões sudo"
        return 1
    fi
}

setup_ntfs_mount() {
    echo "💾 Configurando montagem de partição NTFS..."
    local ERROR_COUNT=0
    local TARGET_UUID="0EF00CA20EF00CA2"
    local MOUNT_POINT="/media/arquivos"
    local DEVICE_PATH=""

    # Verificar dependências
    echo "🔍 Verificando dependências NTFS..."
    for pkg in "ntfs-3g" "util-linux"; do
        if ! check_package_installed "$pkg"; then
            echo "📦 Instalando $pkg..."
            install_package "$pkg" || ((ERROR_COUNT++))
        else
            echo "✅ $pkg já está instalado"
        fi
    done
    
    # Validar UUID e encontrar dispositivo
    echo "🔍 Verificando partição NTFS..."
    DEVICE_PATH=$(sudo blkid | grep "$TARGET_UUID" | cut -d: -f1)
    if [ -z "$DEVICE_PATH" ]; then
        echo "❌ Partição com UUID=$TARGET_UUID não encontrada"
        return 1
    fi
    echo "✅ Partição encontrada em: $DEVICE_PATH"
    
    # Verificar sistema de arquivos
    local FS_TYPE=$(sudo blkid -o value -s TYPE "$DEVICE_PATH")
    if [ "$FS_TYPE" != "ntfs" ]; then
        echo "❌ Sistema de arquivos incompatível: $FS_TYPE (esperado: ntfs)"
        return 1
    fi

    # Verificar se existe diretório em maiúsculo e remover
    if [ -d "/media/ARQUIVOS" ]; then
        echo "🗑️ Removendo diretório em maiúsculo..."
        sudo umount "/media/ARQUIVOS" 2>/dev/null || true
        sudo rm -rf "/media/ARQUIVOS"
    fi

    # Verificar se a partição existe
    if ! sudo blkid | grep -q "$TARGET_UUID"; then
        echo "❌ Partição com UUID=$TARGET_UUID não encontrada"
        return 1
    fi

    # Criar ponto de montagem em minúsculo
    echo "📁 Verificando ponto de montagem em $MOUNT_POINT..."
    if [ ! -d "$MOUNT_POINT" ]; then
        sudo mkdir -p "$MOUNT_POINT"
    fi

    # Ajustar permissões do ponto de montagem
    sudo chown root:root "$MOUNT_POINT"
    sudo chmod 755 "$MOUNT_POINT"

    # Verificar se já existe entrada no fstab para este UUID
    if grep -q "$TARGET_UUID" /etc/fstab; then
        echo "📝 Atualizando entrada existente no fstab..."
        sudo sed -i "\|UUID=$TARGET_UUID|d" /etc/fstab
    fi

    # Adicionar entrada no fstab
    local fstab_line="UUID=$TARGET_UUID $MOUNT_POINT ntfs-3g defaults,uid=$(id -u),gid=$(id -g),umask=022 0 0"
    echo "🔧 Adicionando entrada no fstab..."
    echo "$fstab_line" | sudo tee -a /etc/fstab > /dev/null

    # Desmontar se já estiver montado
    sudo umount "$MOUNT_POINT" 2>/dev/null || true

    # Tentar montar
    echo "🔌 Montando partição..."
    sudo mount "$MOUNT_POINT" || {
        echo "⚠️ Erro ao montar. Removendo entrada do fstab..."
        sudo sed -i "\|$MOUNT_POINT|d" /etc/fstab
        ((ERROR_COUNT++))
    }

    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Partição NTFS configurada com sucesso em $MOUNT_POINT!"
        return 0
    else
        echo "❌ Falha ao configurar partição NTFS"
        return 1
    fi
}

# Menu do sistema
show_system_menu() {
    echo -e "\n${BLUE}Escolha o que deseja configurar:${NC}"
    echo -e "${GREEN}1)${NC} Sistema base e pacotes essenciais"
    echo -e "${GREEN}2)${NC} Ferramentas do sistema"
    echo -e "${GREEN}3)${NC} Configurar sudo sem senha"
    echo -e "${GREEN}4)${NC} Configurar montagem NTFS"
    echo -e "${GREEN}5)${NC} Tudo acima"
    echo -e "${GREEN}0)${NC} Voltar"
    
    read -r choice
    case $choice in
        1) setup_system_base ;;
        2) setup_system_tools ;;
        3) setup_sudo ;;
        4) setup_ntfs_mount ;;
        5)
            setup_system_base
            setup_system_tools
            setup_sudo
            setup_ntfs_mount
            ;;
        0) return ;;
        *) echo "Opção inválida" ;;
    esac
}

# Execução principal
check_root
show_system_menu
