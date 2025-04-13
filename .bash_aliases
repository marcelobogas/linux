alias update="sudo nala update"
alias upgrade="sudo nala upgrade -y"
alias nalai="sudo nala install -y"
alias art="php artisan"
alias nrd="npm run dev"
alias nrb="npm run build"
alias ni="npm install"
alias ci="composer install"
alias cr="composer remove"
alias cda="composer dump-autoload -o"
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
