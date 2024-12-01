#!/bin/bash

RULES_FILE="forwarding_rules.json"

# 检查并安装 jq 和 nc
if ! command -v jq &> /dev/null
then
    echo "jq 未安装。正在安装 jq..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get update && sudo apt-get install -y jq
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y epel-release && sudo yum install -y jq
    else
        echo "无法自动安装 jq，请手动安装。"
        exit 1
    fi
fi

if ! command -v nc &> /dev/null
then
    echo "nc 未安装。正在安装 nc..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get update && sudo apt-get install -y netcat
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y nc
    else
        echo "无法自动安装 nc，请手动安装。"
        exit 1
    fi
fi

# 创建记录文件
if [ ! -f $RULES_FILE ]; then
    echo "{}" > $RULES_FILE
fi

function save_rule {
    jq --argjson rule "$1" '.[$rule.local_port] = $rule' $RULES_FILE > tmp.$$.json && mv tmp.$$.json $RULES_FILE
    echo "规则已保存：$1"
}

function delete_rule {
    jq --arg local_port "$1" 'del(.[$local_port])' $RULES_FILE > tmp.$$.json && mv tmp.$$.json $RULES_FILE
    echo "规则已删除：本地端口 $1"

    # 终止占用端口的进程
    pid=$(netstat -tulnp 2>/dev/null | grep ":$1" | awk '{print $7}' | cut -d'/' -f1)
    if [ ! -z "$pid" ]; then
        sudo kill $pid
        echo "已终止占用端口的进程 PID: $pid"
    fi

    # 删除防火墙规则
    sudo iptables -D INPUT -p tcp --dport "$1" -j ACCEPT
    sudo ip6tables -D INPUT -p tcp --dport "$1" -j ACCEPT
}

function list_rules {
    echo "当前转发规则："
    jq '.' $RULES_FILE
}

function check_forwarding {
    echo "正在检查转发规则状态..."
    rules=$(jq -c '.' $RULES_FILE)
    for rule in $(echo "${rules}" | jq -c 'to_entries[]'); do
        local_port=$(echo "${rule}" | jq -r '.key')
        target_ip=$(echo "${rule}" | jq -r '.value.target_ip')
        echo "检查本地端口 ${local_port} 转发到 ${target_ip} 的状态..."
        if nc -z -v -w5 127.0.0.1 ${local_port}; then
            echo "转发状态：正常"
        else
            echo "转发状态：异常"
        fi
    done
}

function add_rule {
    read -p "请输入转发规则名称: " name
    echo "请选择协议类型: [1] TCP  [2] UDP  [3] TCP/UDP"
    read -p "请输入选择 (1/2/3): " protocol_choice

    case $protocol_choice in
        1)
            protocol="TCP"
            ;;
        2)
            protocol="UDP"
            ;;
        3)
            protocol="TCP/UDP"
            ;;
        *)
            echo "无效选择。请输入1、2或3。"
            return
            ;;
    esac

    read -p "请输入本地端口: " local_port
    read -p "请输入目标 IP: " target_ip
    read -p "请输入目标端口: " target_port

    # 检查是否是 IPv6 地址，如果是则添加方括号
    if [[ $target_ip =~ .*:.* ]]; then
        target_ip="[$target_ip]"
    fi

    # 清理旧的转发规则
    delete_rule "$local_port"

    # 终止所有 socat 进程
    sudo pkill socat

    rule=$(jq -n --arg name "$name" --arg protocol "$protocol" --arg local_port "$local_port" --arg target_ip "$target_ip" --arg target_port "$target_port" '{name: $name, protocol: $protocol, local_port: $local_port, target_ip: $target_ip, target_port: $target_port}')
    save_rule "$rule"

    # 添加防火墙规则
    sudo iptables -I INPUT -p tcp --dport "$local_port" -j ACCEPT
    sudo ip6tables -I INPUT -p tcp --dport "$local_port" -j ACCEPT

    if [[ "$protocol" == "TCP" || "$protocol" == "TCP/UDP" ]]; then
        socat -d -d TCP4-LISTEN:$local_port,fork TCP:$target_ip:$target_port &
        echo "TCP 转发已添加：本地端口 $local_port 到 $target_ip:$target_port"
    fi

    if [[ "$protocol" == "UDP" || "$protocol" == "TCP/UDP" ]]; then
        socat -d -d UDP4-LISTEN:$local_port,fork UDP:$target_ip:$target_port &
        echo "UDP 转发已添加：本地端口 $local_port 到 $target_ip:$target_port"
    fi
}

function modify_rule {
    read -p "请输入要修改的本地端口: " local_port
    delete_rule "$local_port"
    add_rule
}

function main {
    while true; do
        echo "选项: [1] 添加规则  [2] 列出规则  [3] 删除规则  [4] 修改规则 [5] 检查转发状态 [6] 退出"
        read -p "请输入您的选择: " choice
        case $choice in
            1)
                add_rule
                ;;
            2)
                list_rules
                ;;
            3)
                read -p "请输入要删除的本地端口: " local_port
                delete_rule "$local_port"
                ;;
            4)
                modify_rule
                ;;
            5)
                check_forwarding
                ;;
            6)
                break
                ;;
            *)
                echo "无效选择。请输入1到6之间的数字。"
                ;;
        esac
    done
}

main
