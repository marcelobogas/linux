alias update="sudo apt update"
alias upgrade="sudo apt upgrade -y"
alias install="sudo apt install -y"

# Laravel Aliases
alias art="php artisan"
alias ni="npm install"
alias nu="npm update"
alias nrd="npm run dev"
alias nrb="npm run build"
alias ci="composer install"
alias cu="composer update"
alias cr="composer remove"
alias cda="composer dump-autoload -o"
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
