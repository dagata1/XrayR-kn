#!/bin/bash
#====================================================
# XrayR 工具箱
# 适配低内存机器 (128MB+ RAM)
# Repo: https://github.com/dagata1/XrayR-kn
#====================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

cur_dir=$(pwd)
RAW_URL="https://raw.githubusercontent.com/dagata1/XrayR-kn/master"

#=========== 检测 ===========
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用 root 用户运行此脚本！\n" && exit 1

if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue 2>/dev/null | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue 2>/dev/null | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue 2>/dev/null | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /etc/issue 2>/dev/null | grep -Eqi "alpine"; then
    release="alpine"
elif cat /proc/version 2>/dev/null | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version 2>/dev/null | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version 2>/dev/null | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(arch)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi
echo "架构: ${arch}"

XRAYR_REPO="dagata1/XrayR-kn"

#=========== 工具函数 ===========
install_base() {
    if [[ x"${release}" == x"alpine" ]]; then
        apk add --no-cache wget curl unzip tar socat bash
    elif [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt update -y
        apt install wget curl unzip tar cron socat -y
    fi
}

check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    temp=$(systemctl status XrayR 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then return 0; else return 1; fi
}

#=========== XrayR 安装 ===========
install_xrayr() {
    local target_version="$1"

    if [[ -e /usr/local/XrayR/ ]]; then
        rm -rf /usr/local/XrayR/
    fi

    mkdir -p /usr/local/XrayR/
    cd /usr/local/XrayR/

    if [ -z "$target_version" ]; then
        local latest
        latest=$(curl -Ls "https://api.github.com/repos/${XRAYR_REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ -z "$latest" ]]; then
            latest="v0.9.5"
            echo -e "${yellow}GitHub API 不可用，使用默认版本: ${latest}${plain}"
        fi
        target_version="$latest"
        echo -e "检测到 XrayR 最新版本：${target_version}，开始安装"
    else
        if [[ $target_version != v* ]]; then target_version="v${target_version}"; fi
        echo -e "开始安装 XrayR ${target_version}"
    fi

    wget -q -N --no-check-certificate -O /usr/local/XrayR/XrayR-linux.zip \
        "https://github.com/${XRAYR_REPO}/releases/download/${target_version}/XrayR-linux-${arch}.zip"
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 XrayR 失败，请确认 Release 存在${plain}"
        exit 1
    fi

    unzip -o -q XrayR-linux.zip
    rm -f XrayR-linux.zip
    chmod +x XrayR

    mkdir -p /etc/XrayR/ /var/log/XrayR/

    # systemd 服务
    systemctl unmask XrayR 2>/dev/null
    rm -f /etc/systemd/system/XrayR.service
    cat > /etc/systemd/system/XrayR.service << SVC
[Unit]
Description=XrayR Service
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/XrayR/
ExecStart=/usr/local/XrayR/XrayR --config /etc/XrayR/config.yml
Restart=on-failure
RestartSec=10
Nice=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SVC

    # 数据文件
    cp -f geoip.dat /etc/XrayR/ 2>/dev/null || true
    cp -f geosite.dat /etc/XrayR/ 2>/dev/null || true

    # 配置文件
    if [[ ! -f /etc/XrayR/config.yml ]]; then
        cp -f config.yml /etc/XrayR/ 2>/dev/null || true
        if [[ ! -f /etc/XrayR/config.yml ]]; then
            cat > /etc/XrayR/config.yml << 'YMLCONF'
Log:
  Level: warning
  AccessPath: /var/log/XrayR/access.log
  ErrorPath: /var/log/XrayR/error.log
ConnectionConfig:
  Handshake: 4
  ConnIdle: 30
  UplinkOnly: 2
  DownlinkOnly: 4
  BufferSize: 32
Nodes:
  - PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "https://your-panel.com"
      ApiKey: "your-api-key"
      NodeID: 1
      NodeType: V2ray
      Timeout: 30
      EnableVless: false
      SpeedLimit: 0
      DeviceLimit: 0
    ControllerConfig:
      ListenIP: 0.0.0.0
      SendIP: 0.0.0.0
      UpdatePeriodic: 60
      EnableDNS: false
      DNSType: AsIs
      EnableProxyProtocol: false
      EnableFallback: false
      CertConfig:
        CertMode: none
YMLCONF
        fi
    else
        echo -e "${yellow}已存在配置文件，跳过覆盖${plain}"
    fi

    cp -n dns.json /etc/XrayR/ 2>/dev/null || true
    cp -n route.json /etc/XrayR/ 2>/dev/null || true
    cp -n custom_outbound.json /etc/XrayR/ 2>/dev/null || true
    cp -n custom_inbound.json /etc/XrayR/ 2>/dev/null || true
    cp -n rulelist /etc/XrayR/ 2>/dev/null || true

    # 安装管理脚本
    cat > /usr/bin/XrayR << 'XRAYRCMD'
#!/bin/bash
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

XRAYR_BIN="/usr/local/XrayR/XrayR"
XRAYR_CONFIG="/etc/XrayR/config.yml"
XRAYR_LOG="/var/log/XrayR/xrayr.log"
RAW_URL="https://raw.githubusercontent.com/dagata1/XrayR-kn/master"

check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then return 2; fi
    temp=$(systemctl status XrayR 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then return 0; else return 1; fi
}

show_status() {
    echo -e "${cyan}========================================${plain}"
    echo -e "${cyan}         XrayR 运行状态${plain}"
    echo -e "${cyan}========================================${plain}"
    check_status
    local status=$?
    if [[ $status == 0 ]]; then
        echo -e "状态:     ${green}运行中${plain}"
        local pid=$(systemctl show XrayR --property=MainPID 2>/dev/null | cut -d= -f2)
        if [[ -n "$pid" && "$pid" != "0" ]]; then
            echo -e "PID:      $pid"
            if [[ -f /proc/$pid/status ]]; then
                local mem=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
                [[ -n "$mem" ]] && echo -e "内存:     $(( mem / 1024 )) MB"
            fi
        fi
    elif [[ $status == 1 ]]; then
        echo -e "状态:     ${red}未运行${plain}"
    else
        echo -e "状态:     ${red}未安装${plain}"
    fi
    local tm=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
    echo -e "系统内存: ${tm} MB"
    [[ -f "$XRAYR_BIN" ]] && echo -e "版本:     $("$XRAYR_BIN" version 2>/dev/null || echo "unknown")"
    echo -e "${cyan}========================================${plain}"
}

bbr_install() {
    wget -N --no-check-certificate "${RAW_URL}/tcp.sh" -O /tmp/tcp.sh 2>/dev/null
    chmod +x /tmp/tcp.sh
    /tmp/tcp.sh
}

swap_manage() {
    wget -N --no-check-certificate "${RAW_URL}/swap.sh" -O /tmp/swap.sh 2>/dev/null
    chmod +x /tmp/swap.sh
    /tmp/swap.sh
}

streaming_check() {
    wget -N --no-check-certificate "${RAW_URL}/check.sh" -O /tmp/check.sh 2>/dev/null
    chmod +x /tmp/check.sh
    /tmp/check.sh
}

show_menu() {
    echo -e "
  ${cyan}XrayR 管理菜单${plain}  ${yellow}v0.9.5${plain}
  ${green}0${plain}. 返回上级菜单
  ${cyan}————————————————————————${plain}
  ${green}1${plain}. 安装 XrayR         ${green}2${plain}. 更新 XrayR         ${green}3${plain}. 卸载 XrayR
  ${cyan}————————————————————————${plain}
  ${green}4${plain}. 启动 XrayR         ${green}5${plain}. 停止 XrayR         ${green}6${plain}. 重启 XrayR
  ${cyan}————————————————————————${plain}
  ${green}7${plain}. 查看状态           ${green}8${plain}. 查看日志           ${green}9${plain}. 实时日志
  ${cyan}————————————————————————${plain}
  ${green}10${plain}. 编辑配置          ${green}11${plain}. 查看配置
  ${cyan}————————————————————————${plain}
  ${green}12${plain}. 开机自启          ${green}13${plain}. 取消自启          ${green}14${plain}. 内存使用
  ${cyan}————————————————————————${plain}
  ${green}15${plain}. 低内存优化
  ${cyan}————————————————————————${plain}
 "
    echo && read -p "请输入选择 [0-15]: " num
    case "${num}" in
        0) return ;;
        1) bash <(curl -Ls ${RAW_URL}/install.sh) --install ;;
        2)
            read -p "请输入版本号 (留空为最新版): " ver
            bash <(curl -Ls ${RAW_URL}/install.sh) --install "$ver"
            ;;
        3)
            systemctl stop XrayR 2>/dev/null
            systemctl disable XrayR 2>/dev/null
            rm -f /etc/systemd/system/XrayR.service
            rm -rf /etc/systemd/system/XrayR.service.d/
            systemctl daemon-reload 2>/dev/null
            rm -rf /usr/local/XrayR/ /etc/XrayR/
            rm -f /usr/bin/XrayR /usr/bin/xrayr
            echo -e "${green}XrayR 已完全卸载${plain}" ;;
        4) systemctl start XrayR; sleep 2
           check_status; [[ $? == 0 ]] && echo -e "${green}启动成功${plain}" || echo -e "${red}启动失败，使用 XrayR log 查看日志${plain}" ;;
        5) systemctl stop XrayR; echo -e "${green}已停止${plain}" ;;
        6) systemctl restart XrayR; sleep 2
           check_status; [[ $? == 0 ]] && echo -e "${green}重启成功${plain}" || echo -e "${red}重启失败${plain}" ;;
        7) show_status ;;
        8)
            [[ -f "$XRAYR_LOG" ]] && tail -n 50 "$XRAYR_LOG" || journalctl -u XrayR --no-pager -n 50 ;;
        9)
            echo -e "${yellow}按 Ctrl+C 退出${plain}"
            [[ -f "$XRAYR_LOG" ]] && tail -f "$XRAYR_LOG" || journalctl -u XrayR -f ;;
        10)
            if [[ -f "$XRAYR_CONFIG" ]]; then
                local ed="${EDITOR:-vim}"
                command -v "$ed" &>/dev/null || { command -v vim &>/dev/null && ed="vim"; } || { command -v vi &>/dev/null && ed="vi"; } || { command -v nano &>/dev/null && ed="nano"; } || ed="cat"
                [[ "$ed" == "cat" ]] && cat "$XRAYR_CONFIG" || "$ed" "$XRAYR_CONFIG"
                echo -e "${green}已保存，使用 XrayR restart 生效${plain}"
            else echo -e "${red}配置文件不存在${plain}"; fi ;;
        11) [[ -f "$XRAYR_CONFIG" ]] && cat "$XRAYR_CONFIG" || echo -e "${red}配置文件不存在${plain}" ;;
        12) systemctl enable XrayR && echo -e "${green}已设置开机自启${plain}" ;;
        13) systemctl disable XrayR && echo -e "${green}已取消开机自启${plain}" ;;
        14)
            echo -e "${cyan}=== 系统内存 ===${plain}"
            grep -E "MemTotal|MemAvailable|SwapTotal|SwapFree" /proc/meminfo 2>/dev/null | while read line; do echo "  $line"; done
            check_status 2>/dev/null
            if [[ $? == 0 ]]; then
                local pid=$(systemctl show XrayR --property=MainPID 2>/dev/null | cut -d= -f2)
                if [[ -n "$pid" && "$pid" != "0" && -f /proc/$pid/status ]]; then
                    echo -e "\n${cyan}=== XrayR 内存 ===${plain}"
                    grep -E "VmRSS|VmSize|VmSwap" /proc/$pid/status 2>/dev/null
                fi
            fi
            local tm=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
            [[ -n "$tm" && "$tm" -lt 128 ]] && echo -e "\n${yellow}内存低于128MB，建议运行 XrayR tune${plain}" ;;
        15)
            echo -e "${yellow}正在应用低内存优化...${plain}"
            sysctl -w vm.swappiness=10 2>/dev/null || true
            local tm=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
            if [[ -n "$tm" && "$tm" -lt 262144 ]]; then
                mkdir -p /etc/systemd/system/XrayR.service.d/
                cat > /etc/systemd/system/XrayR.service.d/lowmem.conf << LMEOF
[Service]
Environment="GOMEMLIMIT=$(( tm / 2 ))KiB"
MemoryMax=$(( tm / 2 ))K
CPUQuota=50%
LMEOF
                systemctl daemon-reload
                echo -e "${green}已设置 GOMEMLIMIT=$(( tm / 2 ))KiB${plain}"
            fi
            if [[ ! -f /proc/swaps ]] || [[ "$(wc -l < /proc/swaps)" -le 1 ]]; then
                echo -e "${yellow}提示：未检测到 swap，可从工具箱菜单3添加${plain}"
            fi
            echo -e "${green}低内存优化完成${plain}" ;;
        *) echo -e "${red}请输入正确的数字 [0-15]${plain}" ;;
    esac
}

# CLI commands
case "$1" in
    start)    systemctl start XrayR ;;
    stop)     systemctl stop XrayR ;;
    restart)  systemctl restart XrayR ;;
    status)   show_status ;;
    log|logs) [[ -f "$XRAYR_LOG" ]] && tail -n 50 "$XRAYR_LOG" || journalctl -u XrayR --no-pager -n 50 ;;
    live)     [[ -f "$XRAYR_LOG" ]] && tail -f "$XRAYR_LOG" || journalctl -u XrayR -f ;;
    config)
        local ed="${EDITOR:-vim}"
        command -v "$ed" &>/dev/null || { command -v vim &>/dev/null && ed="vim"; } || { command -v vi &>/dev/null && ed="vi"; } || { command -v nano &>/dev/null && ed="nano"; } || ed="cat"
        [[ "$ed" == "cat" ]] && cat "$XRAYR_CONFIG" || "$ed" "$XRAYR_CONFIG" ;;
    show)     cat "$XRAYR_CONFIG" 2>/dev/null || echo -e "${red}配置文件不存在${plain}" ;;
    enable)   systemctl enable XrayR && echo -e "${green}已设置开机自启${plain}" ;;
    disable)  systemctl disable XrayR && echo -e "${green}已取消开机自启${plain}" ;;
    update)   bash <(curl -Ls ${RAW_URL}/install.sh) --install "$2" ;;
    install)  bash <(curl -Ls ${RAW_URL}/install.sh) --install ;;
    uninstall|un)
        systemctl stop XrayR 2>/dev/null; systemctl disable XrayR 2>/dev/null
        rm -f /etc/systemd/system/XrayR.service; rm -rf /etc/systemd/system/XrayR.service.d/
        systemctl daemon-reload 2>/dev/null
        rm -rf /usr/local/XrayR/ /etc/XrayR/; rm -f /usr/bin/XrayR /usr/bin/xrayr
        echo -e "${green}已完全卸载${plain}" ;;
    version)  [[ -f "$XRAYR_BIN" ]] && "$XRAYR_BIN" version || echo "未安装" ;;
    mem|memory)
        echo -e "${cyan}=== 系统内存 ===${plain}"
        grep -E "MemTotal|MemAvailable|SwapTotal|SwapFree" /proc/meminfo 2>/dev/null | while read line; do echo "  $line"; done
        check_status 2>/dev/null
        if [[ $? == 0 ]]; then
            local pid=$(systemctl show XrayR --property=MainPID 2>/dev/null | cut -d= -f2)
            [[ -n "$pid" && "$pid" != "0" && -f /proc/$pid/status ]] && echo -e "\n${cyan}=== XrayR 内存 ===${plain}" && grep -E "VmRSS|VmSize" /proc/$pid/status 2>/dev/null
        fi ;;
    tune)
        sysctl -w vm.swappiness=10 2>/dev/null || true
        local tm=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
        if [[ -n "$tm" && "$tm" -lt 262144 ]]; then
            mkdir -p /etc/systemd/system/XrayR.service.d/
            cat > /etc/systemd/system/XrayR.service.d/lowmem.conf << LMEOF
[Service]
Environment="GOMEMLIMIT=$(( tm / 2 ))KiB"
MemoryMax=$(( tm / 2 ))K
CPUQuota=50%
LMEOF
            systemctl daemon-reload
            echo -e "${green}已设置 GOMEMLIMIT=$(( tm / 2 ))KiB${plain}"
        fi
        echo -e "${green}优化完成${plain}" ;;
    *)
        while true; do
            show_menu
            echo ""; read -p "按 Enter 继续..."
        done ;;
esac
XRAYRCMD

    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr

    systemctl daemon-reload
    systemctl stop XrayR 2>/dev/null
    systemctl enable XrayR

    cd "$cur_dir"

    echo -e "${green}XrayR ${target_version}${plain} 安装完成，已设置开机自启"

    if [[ ! -f /etc/XrayR/config.yml ]]; then
        echo -e "\n全新安装，请先配置：${yellow}XrayR config${plain}"
    else
        systemctl start XrayR; sleep 2
        check_status
        [[ $? == 0 ]] && echo -e "\n${green}XrayR 启动成功${plain}" || echo -e "\n${red}XrayR 启动失败，使用 XrayR log 查看日志${plain}"
    fi

    # 低内存自动优化
    local total_mem=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
    if [[ -n "$total_mem" ]] && [[ "$total_mem" -le 256 ]]; then
        echo -e "\n${yellow}低内存检测 (${total_mem}MB)，应用自动优化...${plain}"
        mkdir -p /etc/systemd/system/XrayR.service.d/
        cat > /etc/systemd/system/XrayR.service.d/lowmem.conf << LMEOF
[Service]
Environment="GOMEMLIMIT=$(( total_mem * 512 ))KiB"
MemoryMax=$(( total_mem * 512 ))K
CPUQuota=50%
LMEOF
        systemctl daemon-reload
        echo -e "${green}已自动设置内存限制${plain}"
    fi
}

#=========== 工具箱菜单 ===========
hub_menu() {
    while true; do
        echo -e "
  ${cyan}========================================${plain}
  ${cyan}           XrayR 工具箱${plain}
  ${cyan}========================================${plain}
  ${green}1${plain}. XrayR 管理菜单        ${yellow}(默认)${plain}
  ${green}2${plain}. 安装/更新 XrayR
  ${green}3${plain}. SWAP 一键管理
  ${green}4${plain}. 流媒体解锁测试
  ${green}5${plain}. TCP 加速 (BBR/锐速)
  ${cyan}————————————————————————${plain}
  ${green}0${plain}. 退出
  ${cyan}========================================${plain}
 "
        echo && read -p "请输入选择 [0-5] (默认1):" choice
        choice=${choice:-1}

        case "${choice}" in
            1)
                if [[ -f /usr/bin/XrayR ]]; then
                    /usr/bin/XrayR
                else
                    echo -e "${yellow}XrayR 尚未安装，将进入安装流程...${plain}"
                    install_base
                    install_xrayr
                fi ;;
            2)
                read -p "请输入版本号 (留空为最新版): " ver
                install_base
                install_xrayr "$ver" ;;
            3)
                wget -N --no-check-certificate "${RAW_URL}/swap.sh" -O /tmp/swap.sh 2>/dev/null
                chmod +x /tmp/swap.sh
                bash /tmp/swap.sh ;;
            4)
                wget -N --no-check-certificate "${RAW_URL}/check.sh" -O /tmp/check.sh 2>/dev/null
                chmod +x /tmp/check.sh
                bash /tmp/check.sh ;;
           5)
                wget -N --no-check-certificate "${RAW_URL}/tcp.sh" -O /tmp/tcp.sh 2>/dev/null
                chmod +x /tmp/tcp.sh
                bash /tmp/tcp.sh ;;
            0) exit 0 ;;
            *) echo -e "${red}请输入正确的数字 [0-5]${plain}" ;;
        esac
        echo ""; read -p "按 Enter 返回工具箱..."
    done
}

#=========== 入口 ===========
if [[ "$1" == "--install" ]]; then
    install_base
    shift
    install_xrayr "$@"
else
    hub_menu
fi
