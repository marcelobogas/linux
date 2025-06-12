#!/usr/bin/zsh

LOCKFILE="/tmp/script.lock"

# Verifica se já existe uma instância rodando
if [ -e "$LOCKFILE" ] && pgrep -f personal_config.sh > /dev/null; then
    echo "O script já está em execução."

    # Pergunta ao usuário se deseja encerrar o processo
    echo -n "Deseja matar o processo em execução? (y/n): "
    read choice

    if [[ "$choice" == "y" ]]; then
        pkill -f personal_config.sh  # Mata o processo pelo nome do script
        sleep 2  # Aguarda um momento para garantir que o processo seja encerrado
        rm -f "$LOCKFILE"  # Remove o arquivo de bloqueio
        echo "Processo encerrado. Você pode rodar o script novamente."
    else
        echo "Saindo..."
        exit 1
    fi
fi

# Cria o arquivo de bloqueio e define um trap para removê-lo ao sair
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"; exit' INT TERM EXIT

# Verifica se o script está sendo executado pelo usuário correto
if [ "$(whoami)" != "marcelo" ]; then
    echo "Este script só pode ser executado pelo usuário marcelo."
    exit 1
fi

set -e  # Para parar a execução em caso de erro
trap 'echo "Erro inesperado! Verifique o script e tente novamente."' ERR

# Modificação opcional do sudoers
echo -n "Deseja modificar o sudoers para evitar senha em comandos sudo? (y/n): "
read choice
if [[ "$choice" == "y" ]]; then
    echo "marcelo ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo || { echo "Erro ao modificar sudoers."; exit 1; }
fi

# Atualização do sistema
echo "Atualizando o sistema..."
sudo apt update && sudo apt dist-upgrade -y || { echo "Erro ao atualizar o sistema"; exit 1; }

# Instalação de pacotes necessários
echo "Verificando e instalando pacotes necessários..."
for pkg in nala zsh curl git; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        sudo apt install -y "$pkg" || { echo "Erro ao instalar $pkg"; exit 1; }
    else
        echo "$pkg já está instalado."
    fi
done

# Verifica e cria o arquivo de aliases se necessário
# Verifica e cria o arquivo de aliases se necessário
if [ ! -f ~/.bash_aliases ]; then
    touch ~/.bash_aliases
    chmod 644 ~/.bash_aliases
fi

echo "Criando e ativando aliases..."
if ! grep -q "alias update=" ~/.bash_aliases; then
    echo "Adicionando novos aliases ao arquivo..."
    cat <<EOF >> ~/.bash_aliases
    alias update="sudo nala update"
    alias upgrade="sudo nala upgrade -y"
    alias nalai="sudo nala install -y"
    alias nalap="sudo nala purge -y"
    alias art="php artisan"
    alias nrd="npm run dev"
    alias nrb="npm run build"
    alias ni="npm install"
    alias ci="composer install"
    alias cu="composer update"
    alias cr="composer remove"
    alias cda="composer dump-autoload -o"
    alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'
    export NVM_DIR="\${XDG_CONFIG_HOME:-$HOME}/nvm"
    [ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
EOF
else
    echo "Aliases já foram adicionados anteriormente."
fi

# Ativa os aliases no Zsh apenas se ainda não estiver ativado
if ! grep -qxF "source ~/.bash_aliases" ~/.zshrc; then
    echo "source ~/.bash_aliases" >> ~/.zshrc
fi

# Instalação da fonte FiraCode
FONT_DIR="$HOME/.fonts"
FONT_NAME="FiraCode"
if [ -d "$FONT_DIR" ] && ls "$FONT_DIR" | grep -qi "$FONT_NAME"; then
    echo "A fonte $FONT_NAME já está instalada."
else
    echo "Baixando e instalando FiraCode Nerd Font..."
    mkdir -m755 "$FONT_DIR"
    cd "$FONT_DIR"
    wget -q --show-progress https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip &&
    unzip FiraCode.zip && rm -rf FiraCode.zip
    fc-cache -fv
    cd ~
fi

# Instalação do Oh-My-Zsh
if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "Oh-My-Zsh já está instalado."
else
    echo "Instalando Oh-My-Zsh..."
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || { echo "Erro ao instalar Oh-My-Zsh."; exit 1; }
fi

# Instalação e configuração do tema Powerlevel10k
THEME_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ -d "$THEME_DIR" ]; then
    echo "O tema Powerlevel10k já está instalado."
else
    echo "Instalando Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$THEME_DIR" || { echo "Erro ao instalar o tema Powerlevel10k."; exit 1; }
fi

# Configuração do tema no .zshrc
if ! grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' ~/.zshrc; then
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> ~/.zshrc
fi

# Instalação dos plugins do Zsh
echo "Instalando e configurando plugins do Zsh..."
PLUGINS_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
PLUGINS=("zsh-users/zsh-autosuggestions" "zsh-users/zsh-syntax-highlighting")

for plugin in "${PLUGINS[@]}"; do
    PLUGIN_NAME=$(basename "$plugin")
    PLUGIN_PATH="$PLUGINS_DIR/$PLUGIN_NAME"

    if [ -d "$PLUGIN_PATH" ]; then
        echo "O plugin $PLUGIN_NAME já está instalado."
    else
        echo "Instalando $PLUGIN_NAME..."
        git clone https://github.com/$plugin "$PLUGIN_PATH" || { echo "Erro ao instalar $PLUGIN_NAME."; exit 1; }
    fi
done

# Configuração final do Zsh
if ! grep -q "plugins=(git zsh-autosuggestions zsh-syntax-highlighting copypath copyfile copybuffer jsontools)" ~/.zshrc; then
    echo "plugins=(git zsh-autosuggestions zsh-syntax-highlighting copypath copyfile copybuffer jsontools)" >> ~/.zshrc
fi

source ~/.zshrc || true
echo "Instalação concluída com sucesso!"
