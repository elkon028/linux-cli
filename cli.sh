#!/usr/bin/env bash

CURRENT_DIR=$(cd $(dirname $0); pwd)
USER=$(who | awk 'NR==1 {print $1}') # 当前登录用户

NODE_MAJOR=16 # nodejs 版本
SKEL_ZSHRC_FILE=/etc/skel/.zshrc
FONTS_TRUETYPE_ROOT=/usr/share/fonts/truetype
OHMYZSH_ROOT=/opt/ohmyzsh
POWERLEVEL10K_ROOT=/opt/powerlevel10k
PYENV_ROOT=/opt/pyenv
JETBRAINS_ROOT=/opt/jetbrains

cd $CURRENT_DIR

LAST_MESSAGE=''

# 定义输出颜色的功能
rmsg() { echo -e "\033[31m$*\033[0m"; }
gmsg() { echo -e "\033[32m$*\033[0m"; }
bmsg() { echo -e "\033[34m$*\033[0m"; }

update_system(){
  apt-get update
  apt-get -y upgrade

  gmsg '系统更新成功'
}

install_package(){
  apt-get install -y zsh htop vim vim-gtk net-tools vlc \
    gnome-tweaks gnome-shell-extension-manager

  cat $CURRENT_DIR/files/vimrc.local > /etc/vim/vimrc.local

  gmsg '软件包安装完成'
}

set_sudo_nopasswd(){
  sed -i 's/%sudo	ALL=(ALL:ALL) ALL/%sudo	ALL=(ALL:ALL) NOPASSWD:ALL/' /etc/sudoers

  gmsg 'sudo免密设置成功'
}

set_eth_resolve_conf(){
  rm -f /etc/resolv.conf
  ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

  # 修改系统网卡ens** 为eth0
  sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/' /etc/default/grub

  update-grub

  gmsg '网卡名 与 resolv.conf 配置成功'
}

set_systime_sync(){
  NTPDATE_CHECK=$(which ntpdate)

  if [ "$?" != "0" ]; then
    apt-get install -y ntpdate
  fi

  ntpdate ntp.aliyun.com
  hwclock --localtime --systohc
  gmsg '双系统时间同步配置成功'
}

set_alias(){
  ALIAS_CHECK=$(cat /etc/profile | grep '# 设置别名')

  if [ "$?" != "0" ]; then
    rmsg '别名已设置(跳过)'
  else
    cat $CURRENT_DIR/files/alias >> /etc/profile
    source /etc/profile

    gmsg '别名设置成功'
  fi
}

install_sshd(){
  SSHD_CHECK=$(which sshd)
  if [ "$?" == "0" ]; then
    rmsg 'sshd服务已存在(跳过)'
  else
    apt-get install -y openssh-server

    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

    sed -i '/RSAAuthentication/d' /etc/ssh/sshd_config

    echo 'RSAAuthentication yes' >> /etc/ssh/sshd_config

    systemctl enable ssh
    systemctl start ssh

    gmsg 'sshd服务安装成功'
  fi
}

install_fonts(){
  if [ $(dpkg --list | grep ttf-mscorefonts-installer | awk '{print $1}') == 'ii' ]; then
    rmsg '字体已安装(跳过)'
  else
    apt-get install -y ttf-mscorefonts-installer

    \cp -r $CURRENT_DIR/fonts/nerd $FONTS_TRUETYPE_ROOT
    \cp -r $CURRENT_DIR/fonts/wps $FONTS_TRUETYPE_ROOT
    chmod -R 755 $FONTS_TRUETYPE_ROOT/nerd
    chmod -R 755 $FONTS_TRUETYPE_ROOT/wps
    chown -R root:root $FONTS_TRUETYPE_ROOT/nerd
    chown -R root:root  $FONTS_TRUETYPE_ROOT/wps

    fc-cache -vfs

    gmsg '字体安装成功'
  fi
}

install_nodejs(){
  NODE_CHECK=$(which node)
  if [ "$?" == "0" ];then
    rmsg 'node已安装(跳过)'
  else
    apt-get install -y curl ca-certificates gnupg

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list

    apt-get update
    apt-get install -y nodejs
    npm install -g yarn

    # 设置 npm 国内源
    npm config set -g registry http://registry.npm.taobao.org
    yarn config set registry https://registry.npm.taobao.org

    gmsg 'node安装成功'
  fi
}

install_git(){
  GIT_CHECK=$(which git)
  if [ "$?" == "0" ];then
    rmsg 'git已安装(跳过)'
  else
    apt-get install -y git

    useradd git -s /sbin/nologin

    git config --system user.name "elkon"
    git config --system user.email "elkon@qq.com"
    git config --system init.defaultBranch "main"
    git config --system push.autoSetupRemote "true"
    git config --system credential.helper store
    git config --system safe.directory "*"
    git config --system alias.cmp '!f() { git pull && git add -A && git commit -m "cmd:add commit push" && git push; }; f'

    gmsg 'git安装成功'
  fi
}

install_pyenv(){
  if [ -d "$PYENV_ROOT" ];then
    rmsg 'pyenv已安装(跳过)'
  else
    git clone https://github.com/pyenv/pyenv.git $PYENV_ROOT
    git clone https://github.com/pyenv/pyenv-virtualenv.git $PYENV_ROOT/plugins/pyenv-virtualenv
    cd $PYENV_ROOT && src/configure && make -C src

    echo "export PYENV_ROOT=$PYENV_ROOT" >> /etc/profile
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> /etc/profile
    echo 'eval "$(pyenv init -)"' >> /etc/profile
    echo 'eval "$(pyenv virtualenv-init -)"' >> /etc/profile

    source /etc/profile

    cd $CURRENT_DIR
    gmsg 'pyenv安装成功'
  fi
}

install_fcitx5(){
  FCITX5_CHECK=$(which fcitx5)
  if [ "$?" == "0" ];then
    rmsg 'fcitx5已安装(跳过)'
  else
    apt-get install -y fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk2 \
    fcitx5-frontend-gtk3 fcitx5-frontend-qt5

    \cp $CURRENT_DIR/files/org.fcitx.Fcitx5.desktop /etc/xdg/autostart/
    chmod 644 /etc/xdg/autostart/org.fcitx.Fcitx5.desktop

    apt-get autoremove --purge -y ibus ibus-* python3-ibus-*

    echo 'GTK_IM_MODULE=fcitx' >> /etc/environment
    echo 'QT_IM_MODULE=fcitx' >> /etc/environment
    echo 'XMODIFIERS=@im=fcitx' >> /etc/environment

    gmsg 'fcitx5安装成功'
  fi
}

uninstall_snap(){
  if [ -f "/etc/apt/preferences.d/nosnap.pref" ]; then
    rmsg 'snap已卸载(跳过)'
  else
    snap remove --purge gtk-common-themes
    snap remove --purge gnome-3-38-2004
    snap remove --purge gnome-42-2204
    snap remove --purge firefox
    snap remove --purge snap-store
    snap remove --purge snapd-desktop-integration
    snap remove --purge bare
    snap remove --purge core20
    snap remove --purge core22
    snap remove --purge snapd

    apt-get autoremove --purge -y snapd

    rm -rf ~/snap
    rm -rf /snap
    rm -rf /var/snap
    rm -rf /var/lib/snapd
    rm -rf /var/cache/snapd

    cat $CURRENT_DIR/files/nosnap.pref > /etc/apt/preferences.d/nosnap.pref

    gmsg 'snap卸载成功'
  fi
}

install_vscode(){
  CODE_CHECK=$(which code)
  if [ "$?" == "0" ];then
    rmsg 'vscode已安装(跳过)'
  else
    wget -O code.deb -c https://az764295.vo.msecnd.net/stable/1a5daa3a0231a0fbba4f14db7ec463cf99d7768e/code_1.84.2-1699528352_amd64.deb
    apt-get install ./code.deb
    rm -f code.deb
    gmsg 'vscode安装成功'
  fi

}

install_chrome(){
  CODE_CHECK=$(which google-chrome)
  if [ "$?" == "0" ];then
    rmsg 'google-chrome已安装(跳过)'
  else
    wget -O google-chrome.deb -c https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt-get install ./google-chrome.deb
    rm -f google-chrome.deb
    gmsg 'google-chrome安装成功'
  fi
}

install_pycharm(){
  if [ -f "/opt/jetbrains/pycharm-2023.2.5/bin/pycharm.sh" ]; then
    rmsg 'pycharm已安装(跳过)'
  else
    mkdir $JETBRAINS_ROOT

    wget -O pycharm.tar.gz -c https://download.jetbrains.com.cn/python/pycharm-professional-2023.2.5.tar.gz
    tar xzf pycharm.tar.gz -C $JETBRAINS_ROOT
    rm -f pycharm.tar.gz

    \cp -r $CURRENT_DIR/idea $JETBRAINS_ROOT
    cat $CURRENT_DIR/files/jetbrains-pycharm.desktop > /usr/share/applications/jetbrains-pycharm.desktop
    cat $CURRENT_DIR/files/jetbrains.vmoptions.sh > /etc/profile.d/jetbrains.vmoptions.sh

    gmsg 'pycharm安装成功'
  fi
}

install_grub2_themes(){
  if [ -d "/boot/grub/themes/tela"]; then
    rmsg 'grub2-themes主题已安装(跳过)'
  else
    wget -O grub2-themes.zip -c https://github.com/vinceliuice/grub2-themes/archive/refs/heads/master.zip
    unzip grub2-themes.zip
    bash ./grub2-themes-master/install.sh -b -t tela -s 1080p
    rm -rf grub2-themes*

    gmsg 'grub2-themes主题安装成功'
  fi
}

install_ohmyzsh(){
  if [ -d "$OHMYZSH_ROOT" ]; then
    rmsg 'oh-my-zsh已安装(跳过)'
  else
    [ -f "$SKEL_ZSHRC_FILE" ] && \cp /etc/skel/.zshrc /etc/skel/.zshrc.orig
    rm -rf $OHMYZSH_ROOT
    rm -rf $POWERLEVEL10K_ROOT
    git clone https://github.com/ohmyzsh/ohmyzsh.git $OHMYZSH_ROOT
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
      $OHMYZSH_ROOT/custom/plugins/zsh-syntax-highlighting
    git clone https://github.com/zsh-users/zsh-autosuggestions \
      $OHMYZSH_ROOT/custom/plugins/zsh-autosuggestions
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
      /opt/powerlevel10k

    cat $CURRENT_DIR/files/zshrc > /etc/skel/.zshrc
    chsh -s /usr/bin/zsh $USER
    chsh -s /usr/bin/zsh
    gmsg 'oh-my-zsh安装成功'
  fi

}

install_windterm(){
  if [ -d "/opt/windterm" ]; then
    rmsg 'windterm已安装(跳过)'
  else
    desktop_file=/opt/windterm/windterm.desktop
    wget -O windterm.tar.gz -c https://github.com/kingToolbox/WindTerm/releases/download/2.5.0/WindTerm_2.5.0_Linux_Portable_x86_64.tar.gz
    tar zxf windterm.tar.gz
    rm -rf windterm.tar.gz

    mv WindTerm_2.5.0 /opt/windterm

    chown -R root:root /opt/windterm
    chmod +x /opt/windterm/WindTerm

    ln -sf /opt/windterm/WindTerm /usr/bin/windterm

    sed -i 's#^Icon=windterm#Icon=/opt/windterm/windterm.png#' $desktop_file

    \cp $desktop_file /usr/share/applications/

    gmsg 'windterm安装成功'
  fi
}

install_jdk8(){
  JAVA_CHECK=$(which java)
  if [ "$?" == "0" ];then
    rmsg 'jdk8已安装(跳过)'
  else
    wget -c https://github.com/elkon028/linux-cli/releases/download/attach/jdk-8u381-linux-x64.tar.gz
    tar zxf jdk-8u381-linux-x64.tar.gz
    mkdir -p /usr/local/java
    mv jdk1.8.0_381 /usr/local/java/jdk8
    rm -f jdk-8u381-linux-x64.tar.gz

    echo 'export JAVA_HOME=/usr/local/java/jdk8'  >> /etc/profile
    echo 'export JRE_HOME=${JAVA_HOME}/jre'  >> /etc/profile
    echo 'export CLASSPATH=.:${JAVA_HOME}/lib:${JRE_HOME}/lib'  >> /etc/profile

    echo 'export PATH=${JAVA_HOME}/bin:$PATH'  >> /etc/profile

    source /etc/profile

    gmsg 'jdk8安装成功'
  fi
}

install_docker(){
  DOCKER_CHECK=$(which docker)
  if [ "$?" == "0" ];then
    rmsg 'docker已安装(跳过)'
  else
    apt-get install -y ca-certificates curl gnupg lsb-release

    mkdir -p /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo "deb [arch="$(dpkg --print-architecture)" \
      signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update

    apt install -y docker-ce docker-ce-cli \
      containerd.io docker-buildx-plugin docker-compose-plugin

    cat $CURRENT_DIR/files/daemon.json > /etc/docker/daemon.json

    systemctl enable docker
    systemctl restart docker

    # 查看是否设置成功
    docker info
    # 查看版本号
    docker -v

    bmsg '拉取 portainer 镜像并创建容器'

    docker pull portainer/portainer-ce:linux-amd64-2.19.3-alpine

    docker run -d -p 9000:9000 --name portainer --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      portainer/portainer-ce:linux-amd64-2.19.3-alpine

    gmsg 'docker安装成功'
  fi
}

install_nextcloud(){
  docker pull nextcloud/all-in-one:latest
  docker run -d \
    --init \
    --sig-proxy=false \
    --name nextcloud-aio-mastercontainer \
    --restart always \
    --publish 8080:8080 \
    --env AIO_DISABLE_BACKUP_SECTION=true \
    --env APACHE_PORT=11000 \
    --env APACHE_IP_BINDING=0.0.0.0 \
    --env NEXTCLOUD_DATADIR=/www/ncdata \
    --volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    nextcloud/all-in-one:latest
}

install_btpanel(){
  wget -O bt-install.sh https://download.bt.cn/install/install-ubuntu_6.0.sh && bash bt-install.sh ed8484bec

  rm -f bt-install.sh
}

linux_cli(){
  echo -e "=================================================================="
  echo -e "\033[32m Linux CLI \033[0m"
  echo -e "=================================================================="
  echo -e ""
  echo -e " (0) 退出                    (ALL) 执行全部"
  echo -e " (1) 系统更新                (2) 安装软件包"
  echo -e " (3) sudo免密码              (4) 网卡名与resolv.conf设置"
  echo -e " (5) 双系统时间同步          (6) 设置指令别名"
  echo -e " (7) 安装 jdk8               (8) 安装 windterm"
  echo -e " (9) 安装 docker             (10) 安装字体"
  echo -e " (11) 安装 sshd              (12) 安装 nodejs"
  echo -e " (13) 安装 git               (14) 安装 pyenv"
  echo -e " (15) 安装 pycharm           (16) 安装 vscode"
  echo -e " (17) 安装 chrome            (18) 安装 grub2 主题"
  echo -e " (19) 安装 ohmyzsh           (20) 安装 fcitx5"
  echo -e " (21) 安装宝塔               (22) 卸载 snap"
  echo -e "\033[32m $LAST_MESSAGE \033[0m"
  echo -e "=================================================================="

  read -p "请输入索引号：" input;

  if [ "$input" == 0 ];then
    exit 0
  elif [ "$input" == 'ALL' ];then
    update_system
    install_package
    set_sudo_nopasswd
    set_eth_resolve_conf
    set_systime_sync
    set_alias
    install_sshd
    install_fonts
    install_nodejs
    install_git

    install_vscode
    install_chrome
    install_pycharm
    install_grub2_themes
    install_ohmyzsh
    install_windterm
    install_docker
    install_jdk8

    install_fcitx5
    uninstall_snap

    install_btpanel
  elif [ "$input" == 1 ];then
    update_system
  elif [ "$input" == 2 ];then
    install_package
  elif [ "$input" == 3 ];then
    set_sudo_nopasswd
  elif [ "$input" == 4 ];then
    set_eth_resolve_conf
  elif [ "$input" == 5 ];then
    set_systime_sync
  elif [ "$input" == 6 ];then
    set_alias
  elif [ "$input" == 7 ];then
    install_jdk8
  elif [ "$input" == 8 ];then
    install_windterm
  elif [ "$input" == 9 ];then
    install_docker
  elif [ "$input" == 10 ];then
    install_fonts
  elif [ "$input" == 11 ];then
    install_sshd
  elif [ "$input" == 12 ];then
    install_nodejs
  elif [ "$input" == 13 ];then
    install_git
  elif [ "$input" == 14 ];then
    install_pyenv
  elif [ "$input" == 15 ];then
    install_pycharm
  elif [ "$input" == 16 ];then
    install_vscode
  elif [ "$input" == 17 ];then
    install_chrome
  elif [ "$input" == 18 ];then
    install_grub2_themes
  elif [ "$input" == 19 ];then
    install_ohmyzsh
  elif [ "$input" == 20 ];then
    install_fcitx5
  elif [ "$input" == 21 ];then
    install_btpanel
  elif [ "$input" == 22 ];then
    uninstall_snap
  fi

  # linux_cli
}

if [ $(whoami) != "root" ];then
  echo "请使用root权限执行此脚本！"
  exit 1;
fi

linux_cli
