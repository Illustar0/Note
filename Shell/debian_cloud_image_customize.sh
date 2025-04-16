#!/bin/bash
FASTFETCH_URL=$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | grep -o 'https://.*fastfetch-linux-amd64.deb')
IP_COUNTRY=$(curl -s https://ipapi.co/country)
IS_CHINA=false
if [[ "$IP_COUNTRY" == "CN" ]]; then
  IS_CHINA=true
  echo "检测到中国 IP，使用国内镜像源"
else
  echo "检测到境外 IP，使用默认配置"
fi

if [ -f "./debian-12-genericcloud-amd64-illustar0-src.qcow2.bak" ]; then
  echo "检测到备份文件，使用备份文件进行定制"
  cp ./debian-12-genericcloud-amd64-illustar0-src.qcow2.bak ./debian-12-genericcloud-amd64-illustar0-src.qcow2
else
  if [ ! -f "./debian-12-genericcloud-amd64-illustar0-src.qcow2" ]; then
    echo 下载镜像
    if [[ "$IS_CHINA" == true ]]; then
      echo "从 USTC 镜像下载 Debian Cloud Image"
      wget https://mirrors.ustc.edu.cn/debian-cdimage/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 -O debian-12-genericcloud-amd64-illustar0-src.qcow2
    else
      echo "从 Debian 官方下载 Debian Cloud Image"
      wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 -O debian-12-genericcloud-amd64-illustar0-src.qcow2
    fi
  fi
  echo "未检测到备份文件，使用源镜像"
  echo "备份源镜像"
  cp ./debian-12-genericcloud-amd64-illustar0-src.qcow2 ./debian-12-genericcloud-amd64-illustar0-src.qcow2.bak
fi


if [[ "$IS_CHINA" == true ]]; then
  virt-customize -a debian-12-genericcloud-amd64-illustar0-src.qcow2 \
  --smp 2 \
  --verbose \
  --timezone "Asia/Shanghai" \
  --append-line "/etc/default/grub:# disables OS prober to avoid loopback detection which breaks booting" \
  --append-line "/etc/default/grub:GRUB_DISABLE_OS_PROBER=true" \
  --run-command "sed -i 's|uname -snrvm|fastfetch|g' /etc/update-motd.d/10-uname" \
  --run-command "sed -i 's|generate_mirrorlists: true|generate_mirrorlists: false|g' /etc/cloud/cloud.cfg.d/01_debian_cloud.cfg" \
  --run-command "update-grub" \
  --run-command "systemctl enable serial-getty@ttyS1.service" \
  --truncate "/etc/apt/mirrors/debian.list" \
  --append-line "/etc/apt/mirrors/debian.list:https://mirrors.ustc.edu.cn/debian/" \
  --append-line "/etc/apt/mirrors/debian.list:https://mirrors.tuna.tsinghua.edu.cn/debian" \
  --append-line "/etc/apt/mirrors/debian.list:https://mirrors.huaweicloud.com/debian" \
  --truncate "/etc/apt/mirrors/debian-security.list" \
  --append-line "/etc/apt/mirrors/debian-security.list:https://mirrors.ustc.edu.cn/debian-security" \
  --append-line "/etc/apt/mirrors/debian-security.list:https://mirrors.tuna.tsinghua.edu.cn/debian-security" \
  --append-line "/etc/apt/mirrors/debian-security.list:https://mirrors.huaweicloud.com/debian-security" \
  --run-command "wget -qO - https://apt.v2raya.org/key/public-key.asc | sudo tee /etc/apt/keyrings/v2raya.asc" \
  --run-command "echo \"deb [signed-by=/etc/apt/keyrings/v2raya.asc] https://apt.v2raya.org/ v2raya main\" | sudo tee /etc/apt/sources.list.d/v2raya.list" \
  --update \
  --install "sudo,qemu-guest-agent,spice-vdagent,bash-completion,git,unzip,zsh,wget,curl,axel,net-tools,iputils-ping,iputils-arping,iputils-tracepath,most,screen,less,vim,bzip2,lldpd,htop,dnsutils,zstd" \
  --install "v2raya,xray" \
  --run-command "curl nxtrace.org/nt | bash" \
  --run-command "wget \"$FASTFETCH_URL\" -O fastfetch-linux-amd64.deb && apt install -y ./fastfetch-linux-amd64.deb && rm ./fastfetch-linux-amd64.deb" \
  --run-command "git clone https://gitee.com/mirrors/oh-my-zsh.git /opt/oh-my-zsh" \
  --run-command "git clone --depth=1 https://gitee.com/romkatv/powerlevel10k.git /opt/oh-my-zsh/custom/themes/powerlevel10k" \
  --run-command "cp /opt/oh-my-zsh/templates/zshrc.zsh-template /etc/skel/.zshrc" \
  --run-command "sed -i 's/ZSH_THEME=\"robbyrussell\"/ZSH_THEME=\"powerlevel10k\/powerlevel10k\"/g' /etc/skel/.zshrc" \
  --run-command "sed -i 's|export ZSH=\"\$HOME/.oh-my-zsh\"|export ZSH=/opt/oh-my-zsh|g' /etc/skel/.zshrc" \
  --copy-in "./.p10k.zsh:/etc/skel/" \
  --append-line "/etc/skel/.zshrc:[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh" \
  --run-command "cp /etc/skel/.zshrc /root/.zshrc" \
  --run-command "cp /etc/skel/.p10k.zsh /root/.p10k.zsh" \
  --append-line "/etc/adduser.conf:DSHELL=/usr/bin/zsh" \
  --append-line "/etc/motd:" \
  --run-command "sed -i 's/SHELL=\/bin\/sh/SHELL=\/usr\/bin\/zsh/g' /etc/default/useradd" \
  --run-command "sed -i 's|shell: /bin/bash|shell: /usr/bin/zsh|g' /etc/cloud/cloud.cfg.d/01_debian_cloud.cfg" \
  --run-command "chsh -s /usr/bin/zsh root" \
  --run-command "apt-get -y autoremove --purge && apt-get -y clean" \
  --append-line "/etc/systemd/timesyncd.conf:NTP=time.apple.com time.windows.com" \
  --delete "/var/log/*.log" \
  --delete "/var/lib/apt/lists/*" \
  --delete "/var/cache/apt/*" \
  --truncate "/etc/machine-id"
else
  virt-customize -a debian-12-genericcloud-amd64-illustar0-src.qcow2 \
  --smp 2 \
  --verbose \
  --timezone "Asia/Shanghai" \
  --append-line "/etc/default/grub:# disables OS prober to avoid loopback detection which breaks booting" \
  --append-line "/etc/default/grub:GRUB_DISABLE_OS_PROBER=true" \
  --run-command "sed -i 's|uname -snrvm|fastfetch|g' /etc/update-motd.d/10-uname" \
  --run-command "sed -i 's|generate_mirrorlists: true|generate_mirrorlists: false|g' /etc/cloud/cloud.cfg.d/01_debian_cloud.cfg" \
  --run-command "update-grub" \
  --run-command "systemctl enable serial-getty@ttyS1.service" \
  --update \
  --install "sudo,qemu-guest-agent,spice-vdagent,bash-completion,git,unzip,zsh,wget,curl,axel,net-tools,iputils-ping,iputils-arping,iputils-tracepath,most,screen,less,vim,bzip2,lldpd,htop,dnsutils,zstd" \
  --run-command "wget -qO - https://apt.v2raya.org/key/public-key.asc | sudo tee /etc/apt/keyrings/v2raya.asc" \
  --run-command "echo \"deb [signed-by=/etc/apt/keyrings/v2raya.asc] https://apt.v2raya.org/ v2raya main\" | sudo tee /etc/apt/sources.list.d/v2raya.list" \
  --install "v2raya,xray" \
  --run-command "curl nxtrace.org/nt | bash" \
  --run-command "wget \"$FASTFETCH_URL\" -O fastfetch-linux-amd64.deb && apt install -y ./fastfetch-linux-amd64.deb && rm ./fastfetch-linux-amd64.deb" \
  --run-command "git clone https://github.com/ohmyzsh/ohmyzsh.git /opt/oh-my-zsh" \
  --run-command "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /opt/oh-my-zsh/custom/themes/powerlevel10k" \
  --run-command "cp /opt/oh-my-zsh/templates/zshrc.zsh-template /etc/skel/.zshrc" \
  --run-command "sed -i 's/ZSH_THEME=\"robbyrussell\"/ZSH_THEME=\"powerlevel10k\/powerlevel10k\"/g' /etc/skel/.zshrc" \
  --run-command "sed -i 's|export ZSH=\"\$HOME/.oh-my-zsh\"|export ZSH=/opt/oh-my-zsh|g' /etc/skel/.zshrc" \
  --copy-in "./.p10k.zsh:/etc/skel/" \
  --append-line "/etc/skel/.zshrc:[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh" \
  --run-command "cp /etc/skel/.zshrc /root/.zshrc" \
  --run-command "cp /etc/skel/.p10k.zsh /root/.p10k.zsh" \
  --append-line "/etc/adduser.conf:DSHELL=/usr/bin/zsh" \
  --run-command "sed -i 's/SHELL=\/bin\/sh/SHELL=\/usr\/bin\/zsh/g' /etc/default/useradd" \
  --run-command "sed -i 's|shell: /bin/bash|shell: /usr/bin/zsh|g' /etc/cloud/cloud.cfg.d/01_debian_cloud.cfg" \
  --run-command "chsh -s /usr/bin/zsh root" \
  --run-command "apt-get -y autoremove --purge && apt-get -y clean" \
  --append-line "/etc/systemd/timesyncd.conf:NTP=time.apple.com time.windows.com" \
  --append-line "/etc/motd:" \
  --truncate "/etc/apt/mirrors/debian.list" \
  --append-line "/etc/apt/mirrors/debian.list:https://mirrors.ustc.edu.cn/debian/" \
  --append-line "/etc/apt/mirrors/debian.list:https://mirrors.tuna.tsinghua.edu.cn/debian" \
  --append-line "/etc/apt/mirrors/debian.list:https://mirrors.huaweicloud.com/debian" \
  --truncate "/etc/apt/mirrors/debian-security.list" \
  --append-line "/etc/apt/mirrors/debian-security.list:https://mirrors.ustc.edu.cn/debian-security" \
  --append-line "/etc/apt/mirrors/debian-security.list:https://mirrors.tuna.tsinghua.edu.cn/debian-security" \
  --append-line "/etc/apt/mirrors/debian-security.list:https://mirrors.huaweicloud.com/debian-security" \
  --delete "/var/log/*.log" \
  --delete "/var/lib/apt/lists/*" \
  --delete "/var/cache/apt/*" \
  --truncate "/etc/machine-id"
fi

virt-sparsify --compress debian-12-genericcloud-amd64-illustar0-src.qcow2 debian-12-genericcloud-amd64-illustar0.qcow2
