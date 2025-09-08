#!/bin/bash

# 脚本出错时立即退出
set -e

# --- 颜色定义 ---
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
NC=$(tput sgr0)

# --- 日志函数 (已修正 log_error) ---
log_info() {
  echo -e "[${GREEN}INFO${NC}] $@"
}

log_warn() {
  echo -e "[${YELLOW}WARN${NC}] $@"
}

log_error() {
  echo -e "[${RED}ERROR${NC}] $@"
}

# --- 依赖检查 ---
for cmd in virt-customize curl basename virt-sparsify tput; do
  if ! command -v "$cmd" &> /dev/null; then
    log_error "命令 '$cmd' 未找到，请先安装它。"
    exit 1
  fi
done


# --- 1. 输入和文件处理 (更安全、更清晰) ---
if [ -z "$1" ]; then
  log_error "用法: $0 <基础镜像.qcow2>"
  exit 1
fi

INPUT_QCOW2="$1"
if [ ! -f "${INPUT_QCOW2}" ]; then
    log_error "输入的镜像文件 '${INPUT_QCOW2}' 不存在。"
    exit 1
fi

BASENAME=$(basename "${INPUT_QCOW2}" .qcow2)
SRC_IMAGE="${BASENAME}-src.qcow2"
FINAL_IMAGE="${BASENAME}-custom.qcow2" # <--- 安全起见，输出到新文件

log_info "准备源镜像以进行定制..."
# 总是从原始输入文件复制一份新的源文件进行操作，保证原始文件安全
cp "${INPUT_QCOW2}" "${SRC_IMAGE}"


# --- 2. 环境检测与变量设置 (避免代码重复) ---
log_info "正在检测网络环境..."
FASTFETCH_URL=$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | grep -o 'https://github.com/fastfetch-cli/fastfetch/releases/download/[^/]*/fastfetch-linux-amd64.deb')
IP_COUNTRY=$(curl -s https://ipapi.co/country)

# 定义变量
MIRROR_COMMANDS=()
OHMYZSH_REPO=""
P10K_REPO=""

if [[ "$IP_COUNTRY" == "CN" ]]; then
  log_info "检测到中国 IP，使用国内镜像源"
  OHMYZSH_REPO="https://gitee.com/mirrors/oh-my-zsh.git"
  P10K_REPO="https://gitee.com/romkatv/powerlevel10k.git"
  # 使用数组存储镜像相关命令
  MIRROR_COMMANDS=(
    --truncate "/etc/apt/mirrors/debian.list"
    --append-line "/etc/apt/mirrors/debian.list:https://mirrors.ustc.edu.cn/debian/"
    --append-line "/etc/apt/mirrors/debian.list:https://mirrors.tuna.tsinghua.edu.cn/debian"
    --append-line "/etc/apt/mirrors/debian.list:https://mirrors.huaweicloud.com/debian"
    --truncate "/etc/apt/mirrors/debian-security.list"
    --append-line "/etc/apt/mirrors/debian-security.list:https://mirrors.ustc.edu.cn/debian-security"
    --append-line "/etc/apt/mirrors/debian-security.list:https://mirrors.tuna.tsinghua.edu.cn/debian-security"
    --append-line "/etc/apt/mirrors/debian-security.list:https://mirrors.huaweicloud.com/debian-security"
  )
else
  log_info "检测到境外 IP，使用默认配置"
  OHMYZSH_REPO="https://github.com/ohmyzsh/ohmyzsh.git"
  P10K_REPO="https://github.com/romkatv/powerlevel10k.git"
  # 境外IP时，MIRROR_COMMANDS 数组为空
fi

# --- 3. 执行镜像定制 (单一、清晰的命令) ---
log_info "开始执行 virt-customize..."

virt-customize -a "${SRC_IMAGE}" \
  --smp 2 \
  --verbose \
  --timezone "Asia/Shanghai" \
  \
  # --- 通用系统配置 ---
  --append-line "/etc/default/grub:GRUB_DISABLE_OS_PROBER=true" \
  --run-command "update-grub" \
  --run-command "systemctl enable serial-getty@ttyS1.service" \
  --run-command "sed -i 's|generate_mirrorlists: true|generate_mirrorlists: false|g' /etc/cloud/cloud.cfg.d/01_debian_cloud.cfg" \
  --append-line "/etc/systemd/timesyncd.conf:NTP=time.apple.com time.windows.com" \
  --run-command "sed -i 's|uname -snrvm|fastfetch|g' /etc/update-motd.d/10-uname" \
  --append-line "/etc/motd:" \
  \
  # --- APT 镜像源配置 (根据网络环境动态插入) ---
  "${MIRROR_COMMANDS[@]}" \
  \
  # --- 软件安装 ---
  --run-command "wget -qO - https://apt.v2raya.org/key/public-key.asc | tee /etc/apt/keyrings/v2raya.asc" \
  --run-command "echo \"deb [signed-by=/etc/apt/keyrings/v2raya.asc] https://apt.v2raya.org/ v2raya main\" | tee /etc/apt/sources.list.d/v2raya.list" \
  --update \
  --install "sudo,qemu-guest-agent,spice-vdagent,bash-completion,git,unzip,zsh,wget,curl,axel,net-tools,iputils-ping,iputils-arping,iputils-tracepath,most,screen,less,vim,bzip2,lldpd,htop,dnsutils,zstd" \
  --install "v2raya,xray" \
  --run-command "curl -L nxtrace.org/nt | bash" \
  --run-command "wget \"$FASTFETCH_URL\" -O fastfetch-linux-amd64.deb && apt install -y ./fastfetch-linux-amd64.deb && rm ./fastfetch-linux-amd64.deb" \
  \
  # --- Zsh 和 Oh-My-Zsh 配置 ---
  --run-command "git clone ${OHMYZSH_REPO} /opt/oh-my-zsh" \
  --run-command "git clone --depth=1 ${P10K_REPO} /opt/oh-my-zsh/custom/themes/powerlevel10k" \
  --run-command "cp /opt/oh-my-zsh/templates/zshrc.zsh-template /etc/skel/.zshrc" \
  --run-command "sed -i 's/ZSH_THEME=\"robbyrussell\"/ZSH_THEME=\"powerlevel10k\/powerlevel10k\"/g' /etc/skel/.zshrc" \
  --run-command "sed -i 's|export ZSH=\"\$HOME/.oh-my-zsh\"|export ZSH=/opt/oh-my-zsh|g' /etc/skel/.zshrc" \
  --copy-in "./.p10k.zsh:/etc/skel/" \
  --append-line "/etc/skel/.zshrc:'[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'" \
  --run-command "cp /etc/skel/.zshrc /root/.zshrc && cp /etc/skel/.p10k.zsh /root/.p10k.zsh" \
  --run-command "chsh -s /usr/bin/zsh root" \
  \
  # --- 设置 Zsh 为默认 Shell ---
  --append-line "/etc/adduser.conf:DSHELL=/usr/bin/zsh" \
  --run-command "sed -i 's/SHELL=\/bin\/sh/SHELL=\/usr\/bin\/zsh/g' /etc/default/useradd" \
  --run-command "sed -i 's|shell: /bin/bash|shell: /usr/bin/zsh|g' /etc/cloud/cloud.cfg.d/01_debian_cloud.cfg" \
  \
  # --- 清理工作 ---
  --run-command "apt-get -y autoremove --purge && apt-get -y clean" \
  --delete "/var/log/*.log" \
  --delete "/var/lib/apt/lists/*" \
  --delete "/var/cache/apt/*" \
  --truncate "/etc/machine-id"

log_info "镜像定制完成，正在清理和压缩镜像..."
virt-sparsify --compress "${SRC_IMAGE}" "${FINAL_IMAGE}"

# 清理临时的源文件
rm "${SRC_IMAGE}"

log_info "✅ 自定义镜像完成！最终镜像文件: ${FINAL_IMAGE}"
