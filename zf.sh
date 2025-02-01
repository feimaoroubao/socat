#!/bin/bash

# 设置颜色和输出函数
red='\e[31m'
green='\e[92m'
yellow='\e[93m'
none='\e[0m'
_red() { echo -e ${red}$@${none}; }
_green() { echo -e ${green}$@${none}; }
_yellow() { echo -e ${yellow}$@${none}; }

err() {
    _red "错误! " $1 && exit 1
}

info() {
    _green "提示! " $1
}

# 检查根权限
[[ $EUID -ne 0 ]] && err "请以 ROOT 用户运行此脚本."

# 检查系统支持（仅支持Ubuntu, Debian, CentOS）
if ! type -P apt-get >/dev/null && ! type -P yum >/dev/null; then
    err "此脚本仅支持 Ubuntu, Debian 或 CentOS 系统."
fi

# 安装必要的软件包
is_pkg="wget unzip jq"
for pkg in $is_pkg; do
    if ! type -P $pkg >/dev/null; then
        if type -P yum >/dev/null; then
            yum install -y $pkg || err "安装 $pkg 失败"
        else
            apt-get update && apt-get -y install $pkg || err "安装 $pkg 失败"
        fi
    fi
done

# 设置路径
is_core="v2ray"
is_core_dir="/etc/$is_core"
is_core_bin="$is_core_dir/bin/$is_core"
is_conf_dir="$is_core_dir/conf"
is_log_dir="/var/log/$is_core"
tmp_dir="/tmp/$is_core"

# 定义下载函数
download() {
    local url=$1
    local path=$2
    wget -qO $path $url || err "下载失败：$url"
}

# 初始化目录结构
init_dirs() {
    rm -rf $tmp_dir
    mkdir -p $is_core_dir $is_core_dir/bin $is_conf_dir $is_log_dir $tmp_dir
}

# 安装/更新V2Ray核心
install_v2ray() {
    v2ray_url="https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip"
    download "$v2ray_url" "/tmp/$is_core.zip"
    unzip -oq "/tmp/$is_core.zip" -d $is_core_dir/bin
    chmod +x $is_core_bin
}

# 创建服务文件
create_service() {
    cat <<EOF > /etc/systemd/system/v2ray.service
[Unit]
Description=V2Ray Service
After=network.target

[Service]
Type=simple
ExecStart=$is_core_bin run -c $is_conf_dir/config.json
StandardOutput=file:$is_log_dir/access.log
StandardError=file:$is_log_dir/error.log
Restart=always
User=root
LimitNOFILE=32767
WorkingDirectory=$is_core_dir

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

# 初始化配置文件
init_config() {
    if [[ ! -f $is_conf_dir/config.json ]]; then
        echo '{
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}' > $is_conf_dir/config.json
    fi
}

# 端口冲突检测
check_port_conflict() {
    local port=$1
    ss -tuln | grep -q ":${port} " && err "端口 $port 已被占用"
}

# 输入验证
validate_number() {
    local num=$1
    [[ "$num" =~ ^[0-9]+$ ]] || err "请输入有效数字"
    (( num >= 1 && num <= 65535 )) || err "端口范围应为 1-65535"
}

validate_ip() {
    local ip=$1
    if ! [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        err "请输入有效的 IPv4 地址"
    fi
}

# 添加配置
add_config() {
    while true; do
        read -p "请输入本地监听端口 (1-65535): " local_port
        validate_number $local_port
        check_port_conflict $local_port
        break
    done

    while true; do
        read -p "请输入目标地址 (IP): " target_addr
        validate_ip $target_addr
        break
    done

    while true; do
        read -p "请输入目标端口 (1-65535): " target_port
        validate_number $target_port
        break
    done

    read -p "请输入备注 (可选): " comment

    # 使用 jq 添加配置
    jq ".inbounds += [{
        \"port\": $local_port,
        \"listen\": \"0.0.0.0\",
        \"protocol\": \"dokodemo-door\",
        \"settings\": {
            \"address\": \"$target_addr\",
            \"port\": $target_port
        },
        \"tag\": \"$comment\"
    }]" $is_conf_dir/config.json > $tmp_dir/config.tmp

    mv $tmp_dir/config.tmp $is_conf_dir/config.json
    info "规则已添加"
    systemctl restart v2ray
    check_service
}

# 修改配置
change_config() {
    list_configs
    read -p "请输入要修改的本地端口: " old_port
    validate_number $old_port

    # 检查配置是否存在
    if ! jq -e ".inbounds[] | select(.port == $old_port)" $is_conf_dir/config.json >/dev/null; then
        err "未找到端口 $old_port 的配置"
    fi

    # 获取旧配置
    old_config=$(jq ".inbounds[] | select(.port == $old_port)" $is_conf_dir/config.json)

    # 读取新值
    read -p "新本地端口 [当前: $(jq -r '.port' <<< "$old_config")]: " new_port
    [[ -z "$new_port" ]] && new_port=$(jq -r '.port' <<< "$old_config")
    validate_number $new_port

    read -p "新目标地址 [当前: $(jq -r '.settings.address' <<< "$old_config")]: " target_addr
    [[ -z "$target_addr" ]] && target_addr=$(jq -r '.settings.address' <<< "$old_config")
    validate_ip $target_addr

    read -p "新目标端口 [当前: $(jq -r '.settings.port' <<< "$old_config")]: " target_port
    [[ -z "$target_port" ]] && target_port=$(jq -r '.settings.port' <<< "$old_config")
    validate_number $target_port

    read -p "新备注 [当前: $(jq -r '.tag' <<< "$old_config")]: " comment
    [[ -z "$comment" ]] && comment=$(jq -r '.tag' <<< "$old_config")

    # 使用 jq 更新配置
    jq "(.inbounds[] | select(.port == $old_port)) |= 
    .port = $new_port |
    .settings.address = \"$target_addr\" |
    .settings.port = $target_port |
    .tag = \"$comment\"" $is_conf_dir/config.json > $tmp_dir/config.tmp

    mv $tmp_dir/config.tmp $is_conf_dir/config.json
    info "配置已更新"
    systemctl restart v2ray
    check_service
}

# 删除配置
delete_config() {
    list_configs
    read -p "请输入要删除的本地端口: " del_port
    validate_number $del_port

    jq "del(.inbounds[] | select(.port == $del_port))" $is_conf_dir/config.json > $tmp_dir/config.tmp
    mv $tmp_dir/config.tmp $is_conf_dir/config.json
    info "端口 $del_port 的配置已删除"
    systemctl restart v2ray
    check_service
}

# 列出所有配置
list_configs() {
    echo -e "\n当前转发规则："
    jq -r '.inbounds[] | "端口：\(.port) => \(.settings.address):\(.settings.port) [备注：\(.tag)]"' $is_conf_dir/config.json
    echo
}

# 检查服务状态
check_service() {
    if ! systemctl is-active --quiet v2ray; then
        _yellow "服务启动失败，请检查配置！"
        journalctl -u v2ray -n 10 --no-pager
        exit 1
    fi
}

# 服务管理菜单
service_menu() {
    echo -e "\n服务管理："
    echo "1. 启动服务"
    echo "2. 停止服务"
    echo "3. 重启服务"
    echo "4. 查看状态"
    echo "5. 返回主菜单"
    
    read -p "请选择操作: " choice
    case $choice in
        1) systemctl start v2ray;;
        2) systemctl stop v2ray;;
        3) systemctl restart v2ray;;
        4) systemctl status v2ray;;
        5) return;;
        *) _red "无效选项";;
    esac
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\nV2Ray 透明代理管理"
        echo "1. 添加转发规则"
        echo "2. 修改转发规则"
        echo "3. 删除转发规则"
        echo "4. 列出所有规则"
        echo "5. 服务管理"
        echo "6. 退出"
        
        read -p "请选择操作: " choice
        case $choice in
            1) add_config;;
            2) change_config;;
            3) delete_config;;
            4) list_configs;;
            5) service_menu;;
            6) exit 0;;
            *) _red "无效选项";;
        esac
    done
}

# 初始化安装流程
init_install() {
    init_dirs
    install_v2ray
    create_service
    init_config
    info "V2Ray 安装完成"
}

# 主流程
if [[ ! -f $is_core_bin ]]; then
    init_install
else
    systemctl stop v2ray 2>/dev/null
    install_v2ray
fi

main_menu
