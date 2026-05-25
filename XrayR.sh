#!/bin/bash
#====================================================
# XrayR 管理脚本
# 安装后位于 /usr/bin/XrayR
# Repo: https://github.com/dagata1/XrayR-kn
#====================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
plain='\033[0m'

XRAYR_BIN="/usr/local/XrayR/XrayR"
XRAYR_CONFIG="/etc/XrayR/config.yml"
XRAYR_LOG="/var/log/XrayR/xrayr.log"
RAW_URL="https://raw.githubusercontent.com/dagata1/XrayR-kn/master"

check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    temp=$(systemctl status XrayR 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_mem() {
    local total_mem
    total_mem=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [[ -n "$total_mem" ]]; then
        echo "$(( total_mem / 1024 ))"
    else
        echo "unknown"
    fi
}

show_status() {
    echo -e "${cyan}========================================${plain}"
    echo -e "${cyan}         XrayR 运行状态${plain}"
    echo -e "${cyan}========================================${plain}"

    check_status
    local status=$?
    if [[ $status == 0 ]]; then
        echo -e "状态:     ${green}运行中${plain}"
        local pid
        pid=$(systemctl show XrayR --property=MainPID 2>/dev/null | cut -d= -f2)
        if [[ -n "$pid" && "$pid" != "0" ]]; then
            echo -e "PID:      $pid"
            if [[ -f /proc/$pid/status ]]; then
                local mem
                mem=$(grep VmRSS /proc/$pid/status 2>/dev/null | awk '{print $2}')
                if [[ -n "$mem" ]]; then
                    echo -e "内存:     $(( mem / 1024 )) MB"
                fi
            fi
        fi
    elif [[ $status == 1 ]]; then
        echo -e "状态:     ${red}未运行${plain}"
        echo -e "查看日志: ${yellow}XrayR log${plain}"
    else
        echo -e "状态:     ${red}未安装${plain}"
    fi

    local mem_info
    mem_info=$(check_mem)
    echo -e "系统内存: ${mem_info} MB"

    if [[ -f "$XRAYR_BIN" ]]; then
        local ver
        ver=$("$XRAYR_BIN" version 2>/dev/null || echo "unknown")
        echo -e "版本:     $ver"
    fi
    echo -e "${cyan}========================================${plain}"
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
        0) exit 0 ;;
        1) install_xrayr ;;
        2) update_xrayr ;;
        3) uninstall_xrayr ;;
        4) start_xrayr ;;
        5) stop_xrayr ;;
        6) restart_xrayr ;;
        7) show_status ;;
        8) view_log ;;
        9) live_log ;;
        10) edit_config ;;
        11) show_config ;;
        12) enable_xrayr ;;
        13) disable_xrayr ;;
        14) check_memory ;;
        15) lowmem_tune ;;
        *) echo -e "${red}请输入正确的数字 [0-15]${plain}" ;;
    esac
}

install_xrayr() {
    bash <(curl -Ls ${RAW_URL}/install.sh) --install
}

update_xrayr() {
    read -p "请输入版本号 (留空为最新版): " version
    bash <(curl -Ls ${RAW_URL}/install.sh) --install "$version"
}

uninstall_xrayr() {
    echo -e "${yellow}正在卸载 XrayR...${plain}"
    systemctl stop XrayR 2>/dev/null
    systemctl disable XrayR 2>/dev/null
    rm -f /etc/systemd/system/XrayR.service
    rm -rf /etc/systemd/system/XrayR.service.d/
    systemctl daemon-reload 2>/dev/null
    rm -rf /usr/local/XrayR/
    rm -rf /etc/XrayR/
    rm -f /usr/bin/XrayR
    rm -f /usr/bin/xrayr
    echo -e "${green}XrayR 已完全卸载${plain}"
}

start_xrayr() {
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${yellow}XrayR 已在运行中${plain}"
    else
        systemctl start XrayR
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR 启动成功${plain}"
        else
            echo -e "${red}XrayR 启动失败，请使用 XrayR log 查看日志${plain}"
        fi
    fi
}

stop_xrayr() {
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${yellow}XrayR 未在运行${plain}"
    else
        systemctl stop XrayR
        sleep 1
        echo -e "${green}XrayR 已停止${plain}"
    fi
}

restart_xrayr() {
    systemctl restart XrayR
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}XrayR 重启成功${plain}"
    else
        echo -e "${red}XrayR 重启失败，请使用 XrayR log 查看日志${plain}"
    fi
}

view_log() {
    if [[ -f "$XRAYR_LOG" ]]; then
        echo -e "${cyan}=== XrayR 日志 (最后50行) ===${plain}"
        tail -n 50 "$XRAYR_LOG"
    elif command -v journalctl &>/dev/null; then
        journalctl -u XrayR --no-pager -n 50
    else
        echo -e "${red}未找到日志文件${plain}"
    fi
}

live_log() {
    echo -e "${yellow}按 Ctrl+C 退出实时日志${plain}"
    if [[ -f "$XRAYR_LOG" ]]; then
        tail -f "$XRAYR_LOG"
    elif command -v journalctl &>/dev/null; then
        journalctl -u XrayR -f
    else
        echo -e "${red}未找到日志文件${plain}"
    fi
}

edit_config() {
    if [[ ! -f "$XRAYR_CONFIG" ]]; then
        echo -e "${red}配置文件不存在${plain}"
        return
    fi
    local editor="${EDITOR:-vim}"
    if ! command -v "$editor" &>/dev/null; then
        if command -v vim &>/dev/null; then editor="vim"
        elif command -v vi &>/dev/null; then editor="vi"
        elif command -v nano &>/dev/null; then editor="nano"
        else editor="cat"
        fi
    fi
    if [[ "$editor" == "cat" ]]; then
        cat "$XRAYR_CONFIG"
    else
        "$editor" "$XRAYR_CONFIG"
        echo -e "${green}配置已保存，使用 XrayR restart 生效${plain}"
    fi
}

show_config() {
    if [[ -f "$XRAYR_CONFIG" ]]; then
        cat "$XRAYR_CONFIG"
    else
        echo -e "${red}配置文件不存在${plain}"
    fi
}

enable_xrayr() {
    systemctl enable XrayR
    echo -e "${green}已设置开机自启${plain}"
}

disable_xrayr() {
    systemctl disable XrayR
    echo -e "${green}已取消开机自启${plain}"
}

check_memory() {
    echo -e "${cyan}=== 系统内存 ===${plain}"
    grep -E "MemTotal|MemAvailable|SwapTotal|SwapFree" /proc/meminfo 2>/dev/null | while read line; do
        echo "  $line"
    done

    check_status 2>/dev/null
    if [[ $? == 0 ]]; then
        local pid
        pid=$(systemctl show XrayR --property=MainPID 2>/dev/null | cut -d= -f2)
        if [[ -n "$pid" && "$pid" != "0" && -f /proc/$pid/status ]]; then
            echo ""
            echo -e "${cyan}=== XrayR 内存使用 ===${plain}"
            grep -E "VmRSS|VmSize|VmSwap" /proc/$pid/status 2>/dev/null | while read line; do
                echo "  $line"
            done
        fi
    fi

    local total_mem
    total_mem=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [[ -n "$total_mem" ]] && [[ "$total_mem" -lt 131072 ]]; then
        echo ""
        echo -e "${yellow}警告: 系统内存低于 128MB，建议添加 swap:${plain}"
        echo "  fallocate -l 256M /swapfile && chmod 600 /swapfile"
        echo "  mkswap /swapfile && swapon /swapfile"
    fi
}

lowmem_tune() {
    echo -e "${yellow}正在应用低内存优化...${plain}"
    sysctl -w vm.swappiness=10 2>/dev/null || true

    local total_mem
    total_mem=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [[ -n "$total_mem" ]] && [[ "$total_mem" -lt 262144 ]]; then
        local mem_limit="$(( total_mem / 2 ))KiB"
        mkdir -p /etc/systemd/system/XrayR.service.d/
        cat > /etc/systemd/system/XrayR.service.d/lowmem.conf << LMEOF
[Service]
Environment="GOMEMLIMIT=$mem_limit"
MemoryMax=$(( total_mem / 2 ))K
CPUQuota=50%
LMEOF
        systemctl daemon-reload
        echo -e "${green}已设置 GOMEMLIMIT=${mem_limit} 和内存限制${plain}"
    fi

    if [[ ! -f /proc/swaps ]] || [[ "$(wc -l < /proc/swaps)" -le 1 ]]; then
        echo -e "${yellow}提示：未检测到 swap，建议添加：${plain}"
        echo "  fallocate -l 256M /swapfile"
        echo "  chmod 600 /swapfile"
        echo "  mkswap /swapfile"
        echo "  swapon /swapfile"
    fi
    echo -e "${green}低内存优化完成${plain}"
}

# CLI commands
case "$1" in
    start)      start_xrayr ;;
    stop)       stop_xrayr ;;
    restart)    restart_xrayr ;;
    status)     show_status ;;
    log|logs)   view_log ;;
    live)       live_log ;;
    config)     edit_config ;;
    show)       show_config ;;
    enable)     enable_xrayr ;;
    disable)    disable_xrayr ;;
    update)     update_xrayr ;;
    install)    install_xrayr ;;
    uninstall|un) uninstall_xrayr ;;
    version)    "$XRAYR_BIN" version 2>/dev/null || echo "XrayR 未安装" ;;
    mem|memory) check_memory ;;
    tune)       lowmem_tune ;;
    *)  # Interactive menu
        while true; do
            show_menu
            echo ""
            read -p "按 Enter 继续..."
        done
        ;;
esac
