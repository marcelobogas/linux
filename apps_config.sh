#!/usr/bin/bash
set -euo pipefail  # Evita execução parcial em caso de erro

LOCKFILE="/tmp/apps_config.lock"

# Verifica se já existe uma instância rodando
if [ -e "$LOCKFILE" ] && pgrep -f apps_config.sh > /dev/null; then
    echo "O script já está em execução."
    echo -n "Deseja matar o processo em execução? (y/n): "
    read choice
    if [[ "$choice" == "y" ]]; then
        pkill -f apps_config.sh
        sleep 2
        rm -f "$LOCKFILE"
        echo "Processo encerrado. Você pode rodar o script novamente."
    else
        echo "Saindo..."
        exit 1
    fi
fi

touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"; exit' INT TERM EXIT

set -e

echo "Instalando pacotes essenciais..."
# Lista de pacotes a serem instalados
PACOTES=(
    gnome-tweaks gnome-shell-extension-manager ca-certificates ubuntu-restricted-extras build-essential synaptic wrk \
    snapd gparted preload vsftpd filezilla neofetch vlc gimp redis supervisor lsb-release gnupg2 apt-transport-https software-properties-common \
    timeshift numlockx net-tools vim gdebi git curl apache2 tree gnupg dirmngr gcc g++ make flatpak curl sassc
)

for pkg in "${PACOTES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        echo "$pkg já está instalado."
    else
        echo "Instalando $pkg..."
        sudo nala install -y "$pkg"
    fi
done

echo "Instalando plugin do Flatpak para GNOME Software..."
if dpkg -s gnome-software-plugin-flatpak &>/dev/null; then
    echo "gnome-software-plugin-flatpak já está instalado."
else
    sudo apt install -y gnome-software-plugin-flatpak
fi

echo "Configurando Flathub..."
if ! flatpak remote-list | grep -q flathub; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
else
    echo "Flathub já está configurado."
fi

echo "Instalando Flatseal via Flatpak..."
if flatpak list | grep -q com.github.tchx84.Flatseal; then
    echo "Flatseal já está instalado."
else
    flatpak install -y flathub com.github.tchx84.Flatseal
fi

echo "Instalando Firefox via Flatpak..."
if flatpak list | grep -q org.mozilla.firefox; then
    echo "Firefox (Flatpak) já está instalado."
else
    flatpak install -y flathub org.mozilla.firefox
fi

echo "Instalando Google Chrome..."
if ! command -v google-chrome > /dev/null; then
    wget -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo gdebi -n /tmp/google-chrome.deb
    rm /tmp/google-chrome.deb
else
    echo "Google Chrome já está instalado."
fi

echo "Instalando Grub Customizer..."
if dpkg -s grub-customizer &>/dev/null; then
    echo "Grub Customizer já está instalado."
else
    wget -O /tmp/grub-customizer.deb https://launchpadlibrarian.net/570407966/grub-customizer_5.1.0-3build1_amd64.deb
    sudo gdebi -n /tmp/grub-customizer.deb
    rm /tmp/grub-customizer.deb
fi

#* Instalar o BOOT REPAIR ***
echo "Instalando Boot Repair..."
if ! command -v boot-repair > /dev/null; then
    sudo add-apt-repository -y ppa:yannubuntu/boot-repair
    sudo nala update
    sudo nala install boot-repair -y
else
    echo "Boot Repair já está instalado."
fi

echo "Instalando Visual Studio Code..."
VSCODE_URL="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
VSCODE_DEB="/tmp/vscode.deb"

# Verifica se o Visual Studio Code já está instalado
if dpkg -s code &>/dev/null; then
    echo "Visual Studio Code já está instalado."
else
    echo "Baixando Visual Studio Code..."
    
    # Testa conexão com o URL antes de baixar
    if curl -s --head "$VSCODE_URL" | grep "200 OK" > /dev/null; then
        wget -O "$VSCODE_DEB" "$VSCODE_URL" || curl -L -o "$VSCODE_DEB" "$VSCODE_URL"
        
        # Confirma se o arquivo foi baixado corretamente
        if file "$VSCODE_DEB" | grep -q 'Debian binary'; then
            echo "Instalando pacote..."
            sudo gdebi -n "$VSCODE_DEB"
            rm "$VSCODE_DEB"
        else
            echo "Erro: O arquivo baixado não parece ser um pacote válido."
            rm -f "$VSCODE_DEB"
        fi
    else
        echo "Erro: Não foi possível acessar o link de download do VS Code."
    fi
fi

CURSOR_DIR="$HOME/Applications/cursor"
CURSOR_APPIMAGE="$CURSOR_DIR/cursor.AppImage"
CURSOR_ICON="$CURSOR_DIR/cursor.png"
CURSOR_DESKTOP="$HOME/.local/share/applications/cursor.desktop"
UPDATE_SCRIPT="$CURSOR_DIR/update-cursor.sh"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/update-cursor.service"
APPIMAGE_URL="https://downloads.cursor.com/production/53b99ce608cba35127ae3a050c1738a959750865/linux/x64/Cursor-1.0.0-x86_64.AppImage"

# 1. Criar a pasta de instalação se não existir
mkdir -p "$CURSOR_DIR"

# 2. Baixar a AppImage somente se não existir ou houver atualização disponível
if [ ! -f "$CURSOR_APPIMAGE" ]; then
    wget -O "$CURSOR_APPIMAGE" "$APPIMAGE_URL"
    chmod +x "$CURSOR_APPIMAGE"
fi

# 3. Criar symlink global para acesso via terminal
if [ ! -L /usr/local/bin/cursor ]; then
    sudo ln -s "$CURSOR_APPIMAGE" /usr/local/bin/cursor
fi

# 4. Baixar o ícone se não existir
if [ ! -f "$CURSOR_ICON" ]; then
    wget -O "$CURSOR_ICON" "https://raw.githubusercontent.com/folke/noice.nvim/main/images/cursor.png" || touch "$CURSOR_ICON"
fi

# 5. Criar atalho no menu de aplicativos
cat > "$CURSOR_DESKTOP" <<EOF
[Desktop Entry]
Name=Cursor
Exec=$CURSOR_APPIMAGE --no-sandbox
Icon=$CURSOR_ICON
Type=Application
Categories=Utility;Development;
EOF
chmod +x "$CURSOR_DESKTOP"

# 6. Criar script de atualização
cat > "$UPDATE_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail
LOGFILE="$CURSOR_DIR/update-cursor.log"
TMP_APPIMAGE="$CURSOR_DIR/cursor.AppImage.tmp"

{
    echo "[$(date)] Iniciando atualização do Cursor IDE..."
    wget -O "\$TMP_APPIMAGE" "$APPIMAGE_URL"
    chmod +x "\$TMP_APPIMAGE"
    
    if file "\$TMP_APPIMAGE" | grep -q 'AppImage'; then
        mv "\$TMP_APPIMAGE" "$CURSOR_APPIMAGE"
        echo "[$(date)] Atualização concluída com sucesso."
    else
        echo "[$(date)] Erro: arquivo baixado inválido."
        rm -f "\$TMP_APPIMAGE"
    fi
} >> "\$LOGFILE" 2>&1
EOF
chmod +x "$UPDATE_SCRIPT"

# 7. Criar serviço systemd para atualizar automaticamente
mkdir -p "$SERVICE_DIR"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Update Cursor IDE

[Service]
ExecStart=$UPDATE_SCRIPT
Type=oneshot

[Install]
WantedBy=default.target
EOF

# 8. Configurar variáveis de ambiente para systemd user
if ! grep -q 'XDG_RUNTIME_DIR' ~/.zshrc; then
    echo 'export XDG_RUNTIME_DIR="/run/user/$(id -u)"' >> ~/.zshrc
fi
if ! grep -q 'DBUS_SESSION_BUS_ADDRESS' ~/.zshrc; then
    echo 'export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"' >> ~/.zshrc
fi
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# 9. Verificar e instalar dependências se necessário
REQUIRED_PKGS=("wget" "dbus-x11" "systemd" "fuse" "libfuse2")
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo "Instalando dependência: $pkg"
        sudo apt-get install -y "$pkg"
    fi
done

# 10. Iniciar o serviço systemd de atualização
systemctl --user daemon-reexec
(systemctl --user enable update-cursor.service)
(systemctl --user start update-cursor.service)

echo "Cursor IDE instalado e configurado com sucesso! Use 'cursor' no terminal para iniciar."

# 11. Para minimizar as aplicações ao clicar no ícone do dock
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize'

echo "Configuração concluída!"
