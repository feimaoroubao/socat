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
    _red "错误!" $1 && exit 1
}

info() {
    _green "提示!" $1
}

# 检查根权限
[[ $EUID -ne 0 ]] && err "请以 ROOT 用户运行此脚本."

# 检查系统支持（仅支持Ubuntu, Debian, CentOS）
if ! type -P apt-get >/dev/null && ! type -P yum >/dev/null; then
    err "此脚本仅支持 Ubuntu, Debian 或 CentOS 系统."
fi

# 安装必要的软件包
is_pkg="wget unzip systemd"
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

# 删除旧目录，创建配置目录
if [[ -d $is_core_dir ]]; then
    rm -rf $is_core_dir || err "无法删除旧目录 $is_core_dir，请手动删除后重试。"
fi
mkdir -p $is_core_dir $is_core_dir/bin $is_conf_dir $is_log_dir $tmp_dir

# 下载V2Ray
v2ray_url="https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip"
download "$v2ray_url" "/tmp/$is_core.zip"
unzip -oq "/tmp/$is_core.zip" -d $is_core_dir/bin
chmod +x $is_core_bin

# 创建服务文件
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

# 重载 systemd
systemctl daemon-reload

# 功能选择菜单
select_action() {
    while true; do
        echo -e "\n选择动作："
        echo "1. 添加配置"
        echo "2. 更改配置"
        echo "3. 查看配置"
        echo "4. 删除配置"
        echo "5. 运行管理"
        echo "6. 查看日志"
        echo "7. 查看运行状态"
        echo "8. 退出"
        read -p "请输入选项: " action
        case $action in
            1) add_config ;;
            2) change_config ;;
            3) view_config ;;
            4) delete_config ;;
            5) run_manage ;;
            6) view_logs ;;
            7) check_v2ray_state ;;
            8) exit 0 ;;
            *) echo "无效选项，请重新选择。" ;;
        esac
    done
}

# 添加配置
add_config() {
    read -p "请输入本地监听端口: " local_port
    read -p "请输入目标地址: " target_addr
    read -p "请输入目标端口: " target_port
    cat <<EOF > $is_conf_dir/config.json
{
  "inbounds": [
    {
      "port": $local_port,
      "listen": "0.0.0.0",
      "protocol": "dokodemo-door",
      "settings": {
        "address": "$target_addr",
        "port": $target_port
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ],
  "log": {
    "loglevel": "info",
    "access": "$is_log_dir/access.log",
    "error": "$is_log_dir/error.log"
  }
}
EOF

    _green "配置文件已生成，已重启V2Ray服务"
    systemctl restart v2ray
}

# 更改配置
change_config() {
    read -p "请输入要更改的本地监听端口 (空表示不更改): " local_port
    read -p "请输入要更改的目标地址 (空表示不更改): " target_addr
    read -p "请输入要更改的目标端口 (空表示不更改): " target_port

    if [[ ! -z "$local_port" ]]; then
      sed -i "s|\"port\": \([0-9]\+\)|\"port\": $local_port|g" $is_conf_dir/config.json
    fi

    if [[ ! -z "$target_addr" ]]; then
      sed -i "s|\"address\": \".*\"|\"address\": \"$target_addr\"|g" $is_conf_dir/config.json
    fi

    if [[ ! -z "$target_port" ]]; then
      sed -i "s|\"port\": \([0-9]\+\)|\"port\": $target_port|g" $is_conf_dir/config.json
    fi

    _green "配置已更新，已重启V2Ray服务"
    systemctl restart v2ray
}

# 删除配置
delete_config() {
    rm -f $is_conf_dir/config.json
    _green "配置已删除。"
    _green "建议添加新配置，重启V2Ray服务"
    systemctl restart v2ray
}

# 查看配置
view_config() {
    if [[ -f $is_conf_dir/config.json ]]; then
      cat $is_conf_dir/config.json
    else
      _red "当前没有配置文件。"
    fi
}

# 查看运行状态
check_v2ray_state() {
    systemctl status v2ray
}

# 查看日志
view_logs() {
    if [[ -f "$is_log_dir/access.log" ]]; then
      echo "访问日志:"
      cat "$is_log_dir/access.log"
    else
      echo "找不到访问日志文件。"
    fi

    if [[ -f "$is_log_dir/error.log" ]]; then
      echo "错误日志:"
      cat "$is_log_dir/error.log"
    else
      echo "找不到错误日志文件。"
    fi
}

# 运行管理功能
run_manage() {
    echo -e "\n运行状态，请选择操作："
    echo "1. 启动"
    echo "2. 停止"
    echo "3. 重启"
    read -p "请输入选项: " action
    case $action in
        1) systemctl start v2ray ;;
        2) systemctl stop v2ray ;;
        3) systemctl restart v2ray ;;
        *) echo "无效选项。" ;;
    esac
}

# 主函数开始
select_action
