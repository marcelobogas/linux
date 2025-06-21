#!/usr/bin/bash

# Configurações globais
set -euo pipefail
IFS=$'\n\t'

# Sistema de logging
log_prefix() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${1:-INFO}"
}

log_debug() {
    echo "$(log_prefix DEBUG) $1" >> "${DIR_CONFIG[logs]}/debug.log"
}

log_info() {
    echo "$(log_prefix INFO) $1" | tee -a "${DIR_CONFIG[logs]}/info.log"
}

log_error() {
    echo "$(log_prefix ERROR) $1" | tee -a "${DIR_CONFIG[logs]}/error.log" >&2
}

# Gerenciamento de dependências
declare -A INSTALLED_PACKAGES
declare -A PACKAGE_VERSIONS

# Sistema de validação
validate_package() {
    local package="$1"
    local required_version="${2:-latest}"
    
    if ! check_package_installed "$package"; then
        log_error "Pacote $package não está instalado"
        return 1
    fi
    
    if [ "$required_version" != "latest" ]; then
        local current_version=$(get_package_version "$package")
        if dpkg --compare-versions "$current_version" lt "$required_version"; then
            log_error "Versão do pacote $package ($current_version) é menor que a requerida ($required_version)"
            return 1
        fi
    fi
    
    return 0
}

# Sistema de backup
create_backup() {
    local file="$1"
    local backup_file="${file}.bak.$(date +%Y%m%d_%H%M%S)"
    
    if [ ! -f "$file" ]; then
        log_error "Arquivo $file não existe"
        return 1
    fi
    
    if cp -p "$file" "$backup_file"; then
        log_info "Backup criado: $backup_file"
        return 0
    else
        log_error "Falha ao criar backup de $file"
        return 1
    fi
}

# Função para fazer backup de diretório ou arquivo
backup_path() {
    local path="$1"
    local backup_dir="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local basename=$(basename "$path")
    local backup_path="${backup_dir}/${basename}_${timestamp}"
    
    # Criar diretório de backup se não existir
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir" || {
            log_error "Falha ao criar diretório de backup $backup_dir"
            return 1
        }
    fi
    
    # Se for arquivo
    if [ -f "$path" ]; then
        cp -p "$path" "$backup_path" || {
            log_error "Falha ao fazer backup do arquivo $path"
            return 1
        }
    # Se for diretório
    elif [ -d "$path" ]; then
        if [ -n "$(ls -A "$path" 2>/dev/null)" ]; then
            cp -rp "$path"/. "$backup_path" || {
                log_error "Falha ao fazer backup do diretório $path"
                return 1
            }
        else
            mkdir -p "$backup_path"
        fi
    else
        log_warning "Caminho $path não existe, nenhum backup necessário"
        return 0
    fi
    
    log_success "Backup criado em: $backup_path"
    echo "$backup_path"
    return 0
}

# Sistema de rollback
declare -a ROLLBACK_ACTIONS=()

register_rollback() {
    ROLLBACK_ACTIONS+=("$1")
}

execute_rollback() {
    log_info "Iniciando rollback..."
    for ((i=${#ROLLBACK_ACTIONS[@]}-1; i>=0; i--)); do
        eval "${ROLLBACK_ACTIONS[i]}" || log_error "Falha em rollback: ${ROLLBACK_ACTIONS[i]}"
    done
    ROLLBACK_ACTIONS=()
}

# Verifica se está rodando como root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        echo "Por favor, não execute este script como root"
        exit 1
    fi
}

# Função para instalar pacotes
install_package() {
    local package="$1"
    local version="${2:-latest}"
    local force="${3:-false}"
    
    # Verificar se já está instalado
    if [ "$force" = "false" ] && check_package_installed "$package"; then
        if [ "$version" = "latest" ]; then
            log_info "Pacote $package já está instalado"
            return 0
        else
            local current_version=$(get_package_version "$package")
            if dpkg --compare-versions "$current_version" ge "$version"; then
                log_info "Pacote $package versão $current_version já atende requisito ($version)"
                return 0
            fi
        fi
    fi
    
    # Registrar ação de rollback
    register_rollback "sudo apt remove -y $package"
    
    # Tentar instalar
    log_info "Instalando $package${version:+ versão $version}..."
    
    # Primeiro tentar atualizar os repositórios
    if ! sudo apt update; then
        log_warning "Falha ao atualizar repositórios, tentando instalar mesmo assim..."
    fi
    
    # Tentar instalar com apt
    if sudo DEBIAN_FRONTEND=noninteractive apt install -y "$package${version:+=}${version}"; then
        log_success "Pacote $package instalado com sucesso via apt"
        return 0
    fi
    
    # Se falhar, tentar com aptitude
    if ! command -v aptitude &> /dev/null; then
        sudo apt install -y aptitude
    fi
    
    if sudo DEBIAN_FRONTEND=noninteractive aptitude install -y "$package${version:+=}${version}"; then
        log_success "Pacote $package instalado com sucesso via aptitude"
        return 0
    fi
    
    log_error "Falha ao instalar $package"
    return 1
    
    # Validar instalação
    if ! check_package_installed "$package"; then
        log_error "Falha ao validar instalação de $package"
        return 1
    fi
    
    log_success "Pacote $package instalado com sucesso"
    return 0
}

# Função para instalar pacotes com tratamento de erro e dependências
install_package_with_deps() {
    local package="$1"
    local version="${2:-latest}"
    local is_optional="${3:-false}"
    
    # Se já estiver instalado, retorna
    if check_package_installed "$package"; then
        return 0
    fi
    
    log_info "Instalando $package${version:+ versão $version}..."
    
    # Tentar instalar via apt primeiro
    if ! sudo DEBIAN_FRONTEND=noninteractive apt install -y "$package${version:+=}${version}"; then
        # Se falhar, tentar resolver dependências com aptitude
        if ! command -v aptitude &> /dev/null; then
            sudo apt install -y aptitude
        fi
        
        if ! sudo DEBIAN_FRONTEND=noninteractive aptitude install -y "$package${version:+=}${version}"; then
            if [ "$is_optional" = "true" ]; then
                log_warning "Falha ao instalar pacote opcional $package"
                return 0
            else
                log_error "Falha ao instalar pacote $package"
                return 1
            fi
        fi
    fi
    
    # Verificar se instalou corretamente
    if ! check_package_installed "$package"; then
        if [ "$is_optional" = "true" ]; then
            log_warning "Pacote opcional $package não foi instalado corretamente"
            return 0
        else
            log_error "Pacote $package não foi instalado corretamente"
            return 1
        fi
    fi
    
    log_success "Pacote $package instalado com sucesso"
    return 0
}

# Sistema de validação de serviços
validate_service() {
    local service="$1"
    local auto_start="${2:-true}"
    local required_status="${3:-running}"
    
    if ! systemctl is-active --quiet "$service"; then
        if [ "$auto_start" = "true" ] && [ "$required_status" = "running" ]; then
            log_info "Iniciando serviço $service..."
            if ! sudo systemctl start "$service"; then
                log_error "Falha ao iniciar serviço $service"
                return 1
            fi
        else
            log_error "Serviço $service não está rodando"
            return 1
        fi
    fi
    
    if ! systemctl is-enabled --quiet "$service" && [ "$auto_start" = "true" ]; then
        log_info "Habilitando serviço $service..."
        if ! sudo systemctl enable "$service"; then
            log_warning "Falha ao habilitar serviço $service"
        fi
    fi
    
    return 0
}

# Sistema de validação de arquivos
validate_file() {
    local file="$1"
    local owner="${2:-}"
    local perms="${3:-}"
    local type="${4:-f}"
    
    if [ ! -"$type" "$file" ]; then
        log_error "Arquivo $file não existe ou não é do tipo correto"
        return 1
    fi
    
    if [ -n "$owner" ]; then
        local current_owner=$(stat -c '%U:%G' "$file")
        if [ "$current_owner" != "$owner" ]; then
            log_error "Proprietário incorreto para $file: $current_owner (esperado: $owner)"
            return 1
        fi
    fi
    
    if [ -n "$perms" ]; then
        local current_perms=$(stat -c '%a' "$file")
        if [ "$current_perms" != "$perms" ]; then
            log_error "Permissões incorretas para $file: $current_perms (esperado: $perms)"
            return 1
        fi
    fi
    
    return 0
}

# Função para garantir existência e permissões de diretórios
ensure_dir() {
    local dir="$1"
    local owner="${2:-$USER}"
    local perms="${3:-755}"
    local sudo_needed=0
    
    # Verificar se precisa de sudo
    if [[ "$dir" == /var/* ]] || [[ "$dir" == /usr/* ]]; then
        sudo_needed=1
    fi
    
    # Criar diretório se não existir
    if [ ! -d "$dir" ]; then
        if [ $sudo_needed -eq 1 ]; then
            sudo mkdir -p "$dir" || {
                log_error "Falha ao criar diretório $dir"
                return 1
            }
        else
            mkdir -p "$dir" || {
                log_error "Falha ao criar diretório $dir"
                return 1
            }
        fi
        log_success "Diretório $dir criado"
    fi
    
    # Ajustar proprietário
    if [ $sudo_needed -eq 1 ]; then
        sudo chown -R "$owner" "$dir" || {
            log_error "Falha ao ajustar proprietário de $dir para $owner"
            return 1
        }
    else
        chown -R "$owner" "$dir" || {
            log_error "Falha ao ajustar proprietário de $dir para $owner"
            return 1
        }
    fi
    
    # Ajustar permissões
    if [ $sudo_needed -eq 1 ]; then
        sudo chmod -R "$perms" "$dir" || {
            log_error "Falha ao ajustar permissões de $dir para $perms"
            return 1
        }
    else
        chmod -R "$perms" "$dir" || {
            log_error "Falha ao ajustar permissões de $dir para $perms"
            return 1
        }
    fi
    
    log_success "Diretório $dir configurado com sucesso"
    return 0
}

# Sistema de validação de espaço em disco
check_disk_space() {
    local path="$1"
    local required_mb="$2"
    local available_kb
    
    # Verificar se o caminho existe
    if [ ! -d "$path" ]; then
        log_error "Diretório $path não existe"
        return 1
    fi
    
    # Obter espaço disponível em KB
    available_kb=$(df -k "$path" | awk 'NR==2 {print $4}')
    if [ -z "$available_kb" ]; then
        log_error "Falha ao verificar espaço em disco para $path"
        return 1
    fi
    
    # Converter para MB
    local available_mb=$((available_kb / 1024))
    
    # Verificar se tem espaço suficiente
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "Espaço insuficiente em $path. Disponível: ${available_mb}MB, Necessário: ${required_mb}MB"
        return 1
    fi
    
    log_success "Espaço suficiente em $path (${available_mb}MB disponível)"
    return 0
}

# Verificação de pacotes instalados
check_package_installed() {
    local package="$1"
    
    # Verificar se está instalado via apt/dpkg
    if command -v dpkg >/dev/null && dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
        log_success "Pacote $package já está instalado (apt)"
        return 0
    fi
    
    # Verificar se é um comando disponível no sistema
    if command -v "$package" >/dev/null; then
        log_success "Comando $package está disponível no sistema"
        return 0
    fi
    
    # Verificar se está instalado via flatpak
    if command -v flatpak >/dev/null && flatpak list | grep -qi "$package"; then
        log_success "Pacote $package já está instalado (flatpak)"
        return 0
    fi
    
    log_warning "Pacote $package não está instalado"
    return 1
}

# Sistema de obtenção de versão de pacotes
get_package_version() {
    local package="$1"
    
    # Tentar obter a versão instalada
    if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
        dpkg -l "$package" | awk '/^ii/ {print $3}'
    else
        echo ""
    fi
}

# Sistema de gerenciamento de repositórios
add_repository() {
    local repo="$1"
    local ppa="${2:-}"
    
    # Se for um PPA, usar add-apt-repository
    if [ -n "$ppa" ]; then
        if ! grep -r "^deb.*$ppa" /etc/apt/ &>/dev/null; then
            log_info "Adicionando PPA: $ppa"
            if ! sudo add-apt-repository -y "ppa:$ppa"; then
                log_error "Falha ao adicionar PPA: $ppa"
                return 1
            fi
        else
            log_info "PPA já está configurado: $ppa"
        fi
        return 0
    fi
    
    # Se for um repositório normal
    if ! grep -r "^deb.*$repo" /etc/apt/ &>/dev/null; then
        log_info "Adicionando repositório: $repo"
        if ! echo "$repo" | sudo tee -a /etc/apt/sources.list.d/custom.list; then
            log_error "Falha ao adicionar repositório: $repo"
            return 1
        fi
        sudo apt update
    else
        log_info "Repositório já está configurado: $repo"
    fi
    
    return 0
}

# Sistema de verificação de repositórios
check_universe_repository() {
    # Verificar se universe está habilitado usando apt-cache policy
    if apt-cache policy | grep -q "^.*universe"; then
        log_success "Repositório universe já está habilitado"
        return 0
    fi
    
    # Se não estiver habilitado, tentar habilitar
    log_info "Habilitando repositório universe..."
    if ! sudo add-apt-repository -y universe; then
        log_error "Falha ao habilitar repositório universe"
        return 1
    fi
    
    # Atualizar lista de pacotes
    if ! sudo apt update; then
        log_error "Falha ao atualizar lista de pacotes após habilitar universe"
        return 1
    fi
    
    log_success "Repositório universe habilitado com sucesso"
    return 0
}

# Função para configurar projeto Laravel
setup_laravel_project() {
    local project_name="$1"
    local project_dir="$2"
    local web_dir="${3:-/var/www/projects}"
    local error_count=0
    
    # Garantir diretórios necessários
    ensure_dir "$web_dir" "$USER:www-data" "775" || ((error_count++))
    ensure_dir "$project_dir/bootstrap/cache" "$USER:www-data" "775" || ((error_count++))
    ensure_dir "$project_dir/storage" "$USER:www-data" "775" || ((error_count++))
    
    # Configurar permissões específicas do Laravel
    find "$project_dir/storage" -type f -exec chmod 664 {} \; || ((error_count++))
    find "$project_dir/storage" -type d -exec chmod 775 {} \; || ((error_count++))
    
    # Criar link simbólico
    local link_path="$web_dir/$project_name"
    if [ -L "$link_path" ]; then
        sudo rm "$link_path"
    fi
    sudo ln -s "$project_dir" "$link_path" || ((error_count++))
    
    # Ajustar SELinux se estiver ativo
    if command -v semanage &> /dev/null; then
        sudo semanage fcontext -a -t httpd_sys_rw_content_t "$project_dir/storage(/.*)?"
        sudo semanage fcontext -a -t httpd_sys_rw_content_t "$project_dir/bootstrap/cache(/.*)?"
        sudo restorecon -Rv "$project_dir"
    fi
    
    if [ $error_count -eq 0 ]; then
        log_success "Projeto $project_name configurado com sucesso"
        return 0
    else
        log_error "Configuração do projeto $project_name concluída com $error_count erro(s)"
        return 1
    fi
}
