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
    timeshift numlockx net-tools vim gdebi git curl apache2 tree gnupg dirmngr gcc g++ make flatpak
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

echo "Configuração concluída!"
