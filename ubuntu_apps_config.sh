#!/usr/bin/bash

##*** não pedir senha para o usuário autenticar alterações via terminal
echo 'marcelo ALL=(ALL:ALL) NOPASSWD: ALL' | sudo tee -a /etc/sudoers.d/user

sudo apt update && sudo apt dist-upgrade -y

##*** instalação da interface NALA para o terminal
sudo apt install nala -y 

##** Download da Fonte FiraCode Nerd Font
mkdir -m755 ~/.fonts &&
cd ~/.fonts &&
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip &&
unzip FiraCode.zip
rm -rf FiraCode.zip
cd /home/$USER/

##** instalação do zsh
sudo nala install zsh -y && sudo nala update

##** instalação do oh-my-zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

##** instalação do tema Powerlevel10k
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k

##** alterar o tema do ZSH
#sudo nano ~/.zshrc
##altere a linha ZSH_THEME="rubbyrussel"'
##ZSH_THEME="powerlevel10k/powerlevel10k"

## adionando plugins úteis
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

##** alterar a linha de plugins para:
# plugins=(git zsh-autosuggestions zsh-syntax-highlighting copypath copyfile copybuffer jsontools)

echo "plugins=(git zsh-autosuggestions zsh-syntax-highlighting copypath copyfile copybuffer jsontools)" > ~/.zshrc

## arquivo para criação de aliases
touch ~/.bash_aliases

echo "alias update="sudo nala update"
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
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm" > tee -a ~/.bash_aliases

echo "if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi" > ~/.zshrc

source ~/.zshrc

sudo nala install gnome-tweaks gnome-shell-extension-manager ca-certificates ubuntu-restricted-extras build-essential synaptic wrk -y

sudo nala install snapd gparted preload vsftpd filezilla neofetch vlc gimp redis supervisor lsb-release gnupg2 apt-transport-https software-properties-common -y

sudo nala install timeshift numlockx net-tools vim gdebi git curl apache2 tree gnupg dirmngr gcc g++ make -y

# flatpak installation
sudo nala install flatpak -y

#enable flathub repository
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# flatseal installation
flatpak install flathub com.github.tchx84.Flatseal

##*** Instalar o Chrome ***
sudo apt update && sudo apt upgrade &&
sudo wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb &&
sudo mv google-chrome-stable_current_amd64.deb /opt/ &&
sudo gdebi /opt/./google-chrome-stable_current_amd64.deb 

##*** php8.4 ***
sudo add-apt-repository ppa:ondrej/php -y && 
sudo nala update &&
sudo nala install php8.4 libapache2-mod-php8.4 php8.4-{dev,common,xml,opcache,mbstring,zip,mysql,pgsql,curl,xdebug,redis,gd,bcmath,intl} unzip -y

##*** instalação do php-fpm
# sudo nala install php8.4-fpm -y
# sudo a2enmod proxy_fcgi setenvif
# sudo a2enconf php8.4-fpm

## habilitar o mode de reescrita de url do apache
sudo a2enmod rewrite &&
sudo a2dismod mpm_event && 
sudo a2enmod mpm_prefork && 
sudo a2enmod php8.4 && 
sudo systemctl restart apache2

##*** Composer ***
curl -sS https://getcomposer.org/installer | php8.4 && sudo mv composer.phar /usr/local/bin/composer && 
sudo touch /home/$USER/.config/composer/composer.json && 
sudo chown -R $USER: /home/$USER/.config/composer && 
sudo chmod 775 /home/$USER/.config/composer/composer.json

echo '{
	"require": {
		"php": "^8.3",
		"laravel/installer": "^5.10"
	}
}' >> /home/$USER/.config/composer/composer.json

cd /home/$USER/.config/composer/ &&
composer install && 
cd ~

##---Setar variável de ambiente do composer global---
echo 'export PATH="$PATH:$HOME/.config/composer/vendor/bin"' >> ~/.bashrc && 
source ~/.bashrc
echo 'export PATH="$PATH:$HOME/.config/composer/vendor/bin"' >> ~/.zshrc && 
source ~/.zshrc

##--- Atualizar versão do composer ---
#Executar esse comando dentro do diretório /home/$USER/.config/composer
#composer self-update

##*** Instalar o nodejs e o npm
# installs nvm (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# download and install Node.js (you may need to restart the terminal)
nvm install 22

# verifies the right Node.js version is in the environment
node -v 

# verifies the right NPM version is in the environment
npm -v 

##*** Instalação do VUE-JS ***
npm install -g @vue/cli

##*** Link para a pasta FTP do Apache ***
sudo mkdir -m755 /var/www/html/ftp -p &&
sudo mkdir -m755 /home/$USER/ftp -p &&
sudo chown -R $USER: /var/www/html/ftp &&
sudo chown -R $USER: /home/$USER/ftp &&
sudo ln -s /var/www/html/ftp /home/$USER/ftp/public

#Acrescentar no final do arquivo /etc/vsftpd.conf
echo 'write_enable=YES' | sudo tee -a /etc/vsftpd.conf &&
echo 'chroot_local_user=YES' | sudo tee -a /etc/vsftpd.conf &&
echo 'allow_writeable_chroot=YES' | sudo tee -a /etc/vsftpd.conf &&
echo 'user_sub_token=$USER' | sudo tee -a /etc/vsftpd.conf &&
echo 'local_root=/home/$USER/ftp/public' | sudo tee -a /etc/vsftpd.conf &&
sudo systemctl restart vsftpd

##*** Instalar PostgreSQL ***
sudo nala update && sudo nala install postgresql -y

##*** Acessar pelo terminal
#sudo su postgres -c psql postgres

##*** Alterar a senha para o usuário
#ALTER USER postgres WITH PASSWORD 'postgres';

##** Instalar o PgAdmin4
curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg
sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list'
sudo nala update && sudo nala install pgadmin4 -y

##*** Habilitar o firewall na inicialização do sistema ***
sudo nala install gufw -y &&
sudo ufw enable && 
sudo ufw default deny incoming && sudo ufw default allow outgoing

#Permissão para as portas
sudo ufw allow 21/tcp &&
sudo ufw allow 22/tcp &&
sudo ufw allow 80/tcp &&
sudo ufw allow 8080/tcp &&
sudo ufw allow 443/tcp &&
sudo ufw allow 8443/tcp &&
sudo ufw status verbose

##*** Instalar acesso seguro - servidor (ssh) ***
sudo nala install -y openssh-server && 
sudo systemctl enable ssh && sudo systemctl restart ssh

*** Instalar Mysql Server ***
sudo nala install mysql-server mysql-client -y

#sudo mysql -u root -p
#CREATE USER 'novousuario'@'localhost' IDENTIFIED BY 'password';
#GRANT ALL PRIVILEGES ON * . * TO 'novousuario'@'localhost';
#FLUSH PRIVILEGES;
#\q

#Permissão para usuário root entrar sem utilizar o sudo
#sudo mysql -u root -p
#ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';
# OR
#ALTER USER 'root'@'localhost' IDENTIFIED BY '';
#FLUSH PRIVILEGES;
#\q 

##** instalação do phpmyadmin
sudo nala install phpmyadmin -y

##** acesso root
# sudo vim /etc/phpmyadmin/config.inc.php
# descomentar a linha (100)
# $cfg['Servers'][$i]['AllowNoPassword'] = TRUE;

##** montar partições NTFS no linux
sudo mkdir -m775 /media/arquivos -p &&
sudo chown -R $USER: /media/arquivos/ &&
echo "UUID=0EF00CA20EF00CA2 /media/arquivos/ ntfs-3g defaults 0 0" | sudo tee -a /etc/fstab

##** instalação do grub-customizer
sudo wget https://launchpadlibrarian.net/570407966/grub-customizer_5.1.0-3build1_amd64.deb && 
sudo gdebi grub-customizer*

##*** Instalar o BOOT REPAIR ***
sudo add-apt-repository ppa:yannubuntu/boot-repair && sudo nala update
sudo nala install boot-repair -y

##*** Instalação do MinIO-Server
wget https://dl.min.io/server/minio/release/linux-amd64/minio_20240611031330.0.0_amd64.deb && 
dpkg -i minio_20240611031330.0.0_amd64.deb && 
sudo groupadd -r minio-user &&
sudo useradd -M -r -g minio-user minio-user && 
sudo mkdir /usr/local/share/minio && 
sudo chown minio-user:minio-user /usr/local/share/minio

#sudo nano /etc/default/minio
echo 'MINIO_VOLUMES="/usr/local/share/minio/"' | sudo tee -a /etc/default/minio
echo 'MINIO_OPTS="-C /etc/minio --address 127.0.0.1:9000"' | sudo tee -a /etc/default/minio
echo 'MINIO_ACCESS_KEY="minioadmin"' | sudo tee -a /etc/default/minio
echo 'MINIO_SECRET_KEY="minioadmin"' | sudo tee -a /etc/default/minio

sudo ufw allow 9000/tcp
sudo systemctl daemon-reload
sudo systemctl start minio
sudo systemctl enable minio

##*** Instalação do Docker
# Add Docker's official GPG key:
sudo nala update &&
sudo install -m 0755 -d /etc/apt/keyrings &&
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc &&
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo nala update

sudo nala install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo groupadd docker &&
sudo usermod -aG docker $USER &&
newgrp docker

# restart terminal session
exec su -l $USER

# test docker installation succefully
#docker run hello-world

sudo systemctl enable docker.service
sudo systemctl enable containerd.service

sudo touch /var/www/html/phpinfo.php && 
echo "<?php phpinfo(); ?>" | sudo tee -a /var/www/html/info.php

sudo nala update && sudo nala upgrade -y && 
sudo nala autoremove -y
