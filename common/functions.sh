#!/usr/bin/bash

# Configurações globais
set -euo pipefail

# Verifica se está rodando como root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        echo "Por favor, não execute este script como root"
        exit 1
    fi
}

# Função para instalar pacotes
install_package() {
    local package=$1
    echo "📦 Verificando $package..."
    if ! dpkg -s "$package" &>/dev/null; then
        echo "⚙️ Instalando $package..."
        sudo apt install -y "$package"
        echo "✅ $package instalado com sucesso"
    else
        echo "✅ $package já está instalado"
    fi
}

# Função para baixar e instalar .deb
install_deb() {
    local url=$1
    local name=$2
    local tmp_file="/tmp/${name}.deb"
    
    if ! dpkg -s "$name" &>/dev/null; then
        echo "⚙️ Baixando $name..."
        wget -O "$tmp_file" "$url" || curl -L -o "$tmp_file" "$url"
        if file "$tmp_file" | grep -q 'Debian binary'; then
            echo "📥 Instalando $name..."
            sudo gdebi -n "$tmp_file"
            rm "$tmp_file"
            echo "✅ $name instalado com sucesso"
        else
            echo "❌ Erro: arquivo baixado inválido"
            rm -f "$tmp_file"
            return 1
        fi
    else
        echo "✅ $name já está instalado"
    fi
}

# Função para adicionar PPA
add_ppa() {
    local ppa=$1
    local grep_pattern=$(echo "$ppa" | cut -d: -f2)
    
    if ! grep -q "^deb .*$grep_pattern" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
        echo "⚙️ Adicionando PPA: $ppa"
        sudo add-apt-repository -y "ppa:$ppa"
        sudo sudo apt install update
    fi
}

# Função para verificar e criar diretório
ensure_dir() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
}
