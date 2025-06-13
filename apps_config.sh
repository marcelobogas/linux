#!/usr/bin/bash

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

# Instalação do Cursor IDE (AI) - Revisada conforme guia oficial
CURSOR_DIR="$HOME/Applications/cursor"
CURSOR_APPIMAGE="$CURSOR_DIR/cursor.AppImage"
CURSOR_ICON="$CURSOR_DIR/cursor.png"
CURSOR_DESKTOP="$HOME/.local/share/applications/cursor.desktop"
UPDATE_SCRIPT="$CURSOR_DIR/update-cursor.sh"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/update-cursor.service"

# 1. Cria a pasta
mkdir -p "$CURSOR_DIR"

# 2. Baixa a AppImage mais recente somente se não existir
if [ ! -f "$CURSOR_APPIMAGE" ]; then
    wget -O "$CURSOR_APPIMAGE" "https://downloads.cursor.com/production/53b99ce608cba35127ae3a050c1738a959750865/linux/x64/Cursor-1.0.0-x86_64.AppImage"
fi

# 3. Torna executável
chmod +x "$CURSOR_APPIMAGE"

# 4. Cria symlink global
if [ ! -L /usr/local/bin/cursor ]; then
    sudo ln -s "$CURSOR_APPIMAGE" /usr/local/bin/cursor
fi

# 5. Baixa o ícone se não existir
if [ ! -f "$CURSOR_ICON" ]; then
    wget -O "$CURSOR_ICON" "https://raw.githubusercontent.com/folke/noice.nvim/main/images/cursor.png" || touch "$CURSOR_ICON"
fi

# 6. Cria o .desktop
cat > "$CURSOR_DESKTOP" <<EOF
[Desktop Entry]
Name=Cursor
Exec=$CURSOR_APPIMAGE --no-sandbox
Icon=$CURSOR_ICON
Type=Application
Categories=Utility;Development;
EOF
chmod +x "$CURSOR_DESKTOP"

# 7. Cria o script de atualização (robusto e com log)
cat > "$UPDATE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -e
APPDIR="$HOME/Applications/cursor"
APPIMAGE_URL="https://downloads.cursor.com/production/53b99ce608cba35127ae3a050c1738a959750865/linux/x64/Cursor-1.0.0-x86_64.AppImage"
LOGFILE="$APPDIR/update-cursor.log"

{
    echo "[$(date)] Iniciando atualização do Cursor IDE..."
    wget -O "$APPDIR/cursor.AppImage.new" "$APPIMAGE_URL"
    chmod +x "$APPDIR/cursor.AppImage.new"
    mv "$APPDIR/cursor.AppImage.new" "$APPDIR/cursor.AppImage"
    echo "[$(date)] Atualização concluída com sucesso."
} >> "$LOGFILE" 2>&1
EOF
chmod +x "$UPDATE_SCRIPT"

# Teste manual sugerido ao usuário
if [ -n "$BASH_VERSION" ]; then
    echo "Para depurar, execute manualmente: bash $UPDATE_SCRIPT e verifique o log em $CURSOR_DIR/update-cursor.log"
fi

# 8. Cria o serviço systemd user
mkdir -p "$SERVICE_DIR"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Update Cursor

[Service]
ExecStart=$UPDATE_SCRIPT
Type=oneshot

[Install]
WantedBy=default.target
EOF

# 9. Configura ambiente para systemd user
if ! grep -q 'XDG_RUNTIME_DIR' ~/.zshrc; then
    echo 'export XDG_RUNTIME_DIR="/run/user/$(id -u)"' >> ~/.zshrc
fi
if ! grep -q 'DBUS_SESSION_BUS_ADDRESS' ~/.zshrc; then
    echo 'export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"' >> ~/.zshrc
fi
# Exporta as variáveis para a sessão atual, se não existirem
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# Detecta shell e orienta o usuário
if [ -n "$BASH_VERSION" ]; then
    echo "AVISO: Você está rodando este script no bash. Recomenda-se abrir um novo terminal zsh para garantir que as variáveis de ambiente estejam corretas. Não execute 'source ~/.zshrc' no bash."
fi

# 10. Instala dependência dbus-x11 se necessário
if ! command -v dbus-launch > /dev/null; then
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt-get install -y dbus-x11
fi

#11. Inicia dbus-launch se necessário
if ! systemctl --user status > /dev/null 2>&1; then
   eval $(dbus-launch --sh-syntax)
fi

# 12. Habilita e inicia o serviço de atualização (não bloqueia o terminal)
(systemctl --user unmask update-cursor.service || true)
(systemctl --user enable update-cursor.service)
(systemctl --user start update-cursor.service)
(systemctl --user status update-cursor.service || true) &

# 13. Mostra tipo de sessão
SESSION_ID=$(loginctl | awk -v user="$(whoami)" '$3==user{print $1; exit}')
if [ -n "$SESSION_ID" ]; then
    loginctl show-session "$SESSION_ID" -p Type
else
    echo "Não foi possível identificar a sessão do usuário para checar o systemd."
fi

echo "Configuração concluída!"
