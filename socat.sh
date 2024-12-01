#!/bin/bash

# 安装必要的工具
install_prerequisites() {
    if ! command -v xray &> /dev/null; then
        echo "Installing xray..."
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
    else
        echo "已安装Xray."
    fi

    if ! command -v jq &> /dev/null; then
        echo "Installing jq..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y epel-release && sudo yum install -y jq
        else
            echo "Unsupported package manager."
        fi
    else
        echo "已安装jq."
    fi
}

# 检测 IP 格式
detect_ip_version() {
    if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ipv4"
    else
        echo "ipv6"
    fi
}

# 添加规则函数
add_rule() {
    echo "请输入规则名称: "
    read -r name
    if [ -f "${name}.json" ]; then
        echo "规则 $name 已存在。"
        return
    fi

    echo "请输入监听端口: "
    read -r listen_port
    if ! [[ "$listen_port" =~ ^[0-9]+$ ]] ; then
        echo "请输入有效的端口号。"
        return
    fi
    
    echo "请输入目标IP地址: "
    read -r target_ip
    
    echo "请输入目标端口: "
    read -r target_port
    if ! [[ "$target_port" =~ ^[0-9]+$ ]] ; then
        echo "请输入有效的端口号。"
        return
    fi

    echo "请选择协议（TCP/UDP）, 默认TCP: "
    read -r protocol
    protocol=${protocol:-TCP}
    
    ip_version=$(detect_ip_version "$target_ip")

    # 设置 IPv6 地址格式
    if [ "$ip_version" = "ipv6" ]; then
        target_ip="[$target_ip]"
    fi

    local file="${name}.json"

    cat << EOF > "$file"
{
  "inbounds": [{
    "port": $listen_port,
    "protocol": "dokodemo-door",
    "settings": {
      "network": "$protocol",
      "followRedirect": true
    },
    "listen": "0.0.0.0"
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {
      "address": "$target_ip",
      "port": $target_port
    }
  }]
}
EOF
    echo "已添加规则 $name"
    xray run -c "$file" &
}

# 显示已添加规则
list_rules() {
    echo "已添加的规则:"
    for rule in *.json; do
        if [ -e "$rule" ]; then
            echo "${rule%.json}"
            jq -r '.inbounds[0].port, .outbounds[0].settings.address, .outbounds[0].settings.port' "$rule"
        fi
    done
}

# 删除指定的规则
delete_rule() {
    echo "请输入要删除的规则名称: "
    read -r name
    local rulefile="${name}.json"
    if [ -f "$rulefile" ]; then
        # 查找并杀掉与规则相关的xray进程
        pid=$(ps ax | grep "xray run -c $rulefile" | grep -v grep | awk '{print $1}')
        if [ -n "$pid" ]; then
            kill $pid
            echo "规则进程已停止"
        fi
        rm "$rulefile"
        echo "规则 $name 已删除"
    else
        echo "规则不存在"
    fi
}

# 测试规则是否运行
test_rule() {
    echo "请输入要测试的规则名称: "
    read -r name
    local rulefile="${name}.json"
    if [ -f "$rulefile" ]; then
        listen_port=$(jq -r '.inbounds[0].port' "$rulefile")
    
        # 使用nc（netcat）来测试端口是否可以连接
        if command -v nc -z localhost $listen_port; then
            echo "规则 $name 在监听端口上运行"
        else
            echo "规则 $name 未运行或无法连接"
        fi
    else
        echo "无法找到规则文件"
    fi
}

# 主函数
main() {
    install_prerequisites
    
    while true; do
        echo -e "\n1. 添加规则\n2. 查看已添加规则\n3. 删除规则\n4. 测试规则\n5. 退出"
        read -p "请选择功能: " choice
        
        case $choice in
            1) add_rule ;;
            2) list_rules ;;
            3) delete_rule ;;
            4) test_rule ;;
            5) break ;;
            *) echo "无效选项，请重试。" ;;
        esac
    done
}

main
