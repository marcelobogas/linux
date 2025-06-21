#!/usr/bin/bash

# Importar configurações comuns
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/common/config.sh"
FUNCTIONS_FILE="$SCRIPT_DIR/common/functions.sh"

echo -e "\n🔍 Verificando arquivos de configuração..."

# Verificar e carregar functions.sh
if [ ! -f "$FUNCTIONS_FILE" ]; then
    echo -e "${RED}❌ Arquivo de funções não encontrado: $FUNCTIONS_FILE${NC}"
    exit 1
fi

source "$FUNCTIONS_FILE"

# Verificar e carregar config.sh
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Arquivo de configuração não encontrado: $CONFIG_FILE${NC}"
    exit 1
fi

source "$CONFIG_FILE"

# Validar estrutura de diretórios
echo -e "\n🔍 Verificando estrutura do projeto..."
for dir in "common" "setup"; do
    if [ ! -d "$SCRIPT_DIR/$dir" ]; then
        echo -e "${RED}❌ Diretório necessário não encontrado: $dir${NC}"
        exit 1
    fi
done

# Verificar scripts necessários
echo -e "\n🔍 Verificando scripts..."
REQUIRED_SCRIPTS=(
    "setup/system.sh"
    "setup/development.sh"
    "setup/theme.sh"
)

MISSING_SCRIPTS=0
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$script" ]; then
        echo -e "${RED}❌ Script não encontrado: $script${NC}"
        MISSING_SCRIPTS=1
    fi
done

if [ $MISSING_SCRIPTS -eq 1 ]; then
    echo -e "${RED}❌ Alguns scripts necessários estão faltando. Verifique a instalação.${NC}"
    exit 1
fi

clear

echo -e "${BOLD}=== 🚀 Script de Configuração Linux ===${NC}"
echo -e "Versão: 1.0.0\n"
echo -e "${BLUE}Status do Sistema:${NC}"
echo -e "📍 Usuário: ${BOLD}$USER_NAME${NC}"
echo -e "📍 Diretório: ${BOLD}$SCRIPT_DIR${NC}"
echo -e "📍 Sistema: ${BOLD}$(uname -s) $(uname -r)${NC}\n"

# Verifica se está rodando como root
if [ "$EUID" -eq 0 ]; then
    echo "Por favor, não execute este script como root"
    exit 1
fi

# Função para executar scripts
run_script() {
    local script=$1
    local description=$2
    
    echo -e "\n${BLUE}=== Executando: $description ===${NC}"
    echo -e "⏳ Iniciando em 3 segundos..."
    sleep 1
    echo -e "⌛ 2..."
    sleep 1
    echo -e "⏳ 1..."
    sleep 1
    
    if [ -f "$script" ]; then
        echo -e "\n📋 Detalhes da execução:"
        echo -e "📍 Script: $script"
        echo -e "📍 Descrição: $description"
        echo -e "📍 Hora início: $(date '+%H:%M:%S')\n"
        
        chmod +x "$script"
        bash "$script"
        local STATUS=$?
        
        echo -e "\n📊 Resultado da execução:"
        echo -e "📍 Hora término: $(date '+%H:%M:%S')"
        
        if [ $STATUS -eq 0 ]; then
            echo -e "${GREEN}✅ $description concluído com sucesso${NC}"
        else
            echo -e "${RED}❌ Erro ao executar $description (código: $STATUS)${NC}"
            echo -e "${YELLOW}⚠️  Verifique o log acima para mais detalhes${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Script não encontrado: $script${NC}"
        return 1
    fi
}

# Menu de opções
show_menu() {
    echo -e "\n${BLUE}Escolha uma opção:${NC}"
    echo -e "${GREEN}1)${NC} Configuração do Sistema"
    echo -e "${GREEN}2)${NC} Ambiente de Desenvolvimento"
    echo -e "${GREEN}3)${NC} Personalização e Tema"
    echo -e "${GREEN}4)${NC} Executar todas as opções"
    echo -e "${GREEN}0)${NC} Sair"
    echo -e "\nDigite sua escolha: "
}

# Loop principal
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1)
            run_script "setup/system.sh" "Configuração do Sistema"
            ;;
        2)
            run_script "setup/development.sh" "Ambiente de Desenvolvimento"
            ;;
        3)
            run_script "setup/theme.sh" "Personalização e Tema"
            ;;
        4)
            echo -e "\n${BLUE}=== Executando todas as configurações ===${NC}"
            run_script "setup/system.sh" "Configuração do Sistema"
            run_script "setup/development.sh" "Ambiente de Desenvolvimento"
            run_script "setup/theme.sh" "Personalização e Tema"
            echo -e "${GREEN}✅ Todas as configurações foram concluídas${NC}"
            ;;
        0)
            echo -e "\n${GREEN}👋 Até mais!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}❌ Opção inválida${NC}"
            ;;
    esac
done
