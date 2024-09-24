#! /bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# ====================================================
# System Request:CentOS 6+ 、Debian 7+、Ubuntu 14+
# Author: Rat's
# Dscription: Socat一键脚本
# Version: 1.9
# ====================================================

Green="\033[32m"
Font="\033[0m"
Blue="\033[33m"
CONFIG_FILE="/root/socat_config.txt"

rootness(){
    if [[ $EUID -ne 0 ]]; then
       echo "Error: This script must be run as root!" 1>&2
       exit 1
    fi
}

checkos(){
    if [[ -f /etc/redhat-release ]]; then
        OS=CentOS
    elif cat /etc/issue | grep -q -E -i "debian"; then
        OS=Debian
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        OS=Ubuntu
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        OS=CentOS
    elif cat /proc/version | grep -q -E -i "debian"; then
        OS=Debian
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        OS=Ubuntu
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        OS=CentOS
    else
        echo "Not supported OS, Please reinstall OS and try again."
        exit 1
    fi
}

disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}

disable_iptables(){
    systemctl stop firewalld.service >/dev/null 2>&1
    systemctl disable firewalld.service >/dev/null 2>&1
    service iptables stop >/dev/null 2>&1
    chkconfig iptables off >/dev/null 2>&1
}

get_ip(){
    ip=`curl -s http://whatismyip.akamai.com`
}

config_socat(){
    echo -e "${Green}请输入Socat配置信息！${Font}"
    read -p "请输入本地端口:" port1
    read -p "请输入远程端口:" port2
    read -p "请输入远程IP:" socatip

    # 选择协议
    echo -e "${Green}请选择协议类型:${Font}"
    echo -e "1. TCP"
    echo -e "2. UDP"
    echo -e "3. TCP和UDP"
    read -p "请输入选择（1/2/3）:" protocol_choice

    case $protocol_choice in
        1)
            protocol="TCP"
            ;;
        2)
            protocol="UDP"
            ;;
        3)
            protocol="TCP+UDP"
            ;;
        *)
            echo "无效选择，默认使用TCP。"
            protocol="TCP"
            ;;
    esac

    # 追加配置到文件
    echo "port1=${port1}" >> $CONFIG_FILE
    echo "port2=${port2}" >> $CONFIG_FILE
    echo "socatip=${socatip}" >> $CONFIG_FILE
    echo "protocol=${protocol}" >> $CONFIG_FILE
    echo "------------------------" >> $CONFIG_FILE
}

start_socat(){
    # 从配置文件中读取最新配置
    if [[ -f $CONFIG_FILE ]]; then
        source $CONFIG_FILE
    else
        echo "配置文件不存在，无法启动Socat。"
        exit 1
    fi

    echo -e "${Green}正在配置Socat...${Font}"
    
    # 启动对应的 Socat 进程
    if [[ "$protocol" == "TCP" ]]; then
        nohup socat TCP4-LISTEN:${port1},reuseaddr,fork TCP4:${socatip}:${port2} >> /root/socat.log 2>&1 &
    elif [[ "$protocol" == "UDP" ]]; then
        nohup socat UDP4-LISTEN:${port1},reuseaddr,fork UDP4:${socatip}:${port2} >> /root/socat.log 2>&1 &
    elif [[ "$protocol" == "TCP+UDP" ]]; then
        nohup socat TCP4-LISTEN:${port1},reuseaddr,fork TCP4:${socatip}:${port2} >> /root/socat.log 2>&1 &
        nohup socat UDP4-LISTEN:${port1},reuseaddr,fork UDP4:${socatip}:${port2} >> /root/socat.log 2>&1 &
    fi

    get_ip
    sleep 3
    echo
    echo -e "${Green}Socat安装并配置成功!${Font}"
    echo -e "${Blue}你的本地端口为:${port1}${Font}"
    echo -e "${Blue}你的远程端口为:${port2}${Font}"
    echo -e "${Blue}你的本地服务器IP为:${ip}${Font}"
}

install_socat(){
    echo -e "${Green}即将安装Socat...${Font}"
    if [ "${OS}" == 'CentOS' ]; then
        yum install -y socat
    else
        apt-get -y update
        apt-get install -y socat
    fi
    if [ -s /usr/bin/socat ]; then
        echo -e "${Green}Socat安装完成！${Font}"
    fi
}

status_socat(){
    if [ -s /usr/bin/socat ]; then
        echo -e "${Green}检测到Socat已存在，并跳过安装步骤！${Font}"
        main_x
    else
        main_y
    fi
}

query_socat(){
    echo -e "${Green}当前Socat转发信息:${Font}"

    # 从配置文件中读取
    if [[ -f $CONFIG_FILE ]]; then
        while IFS= read -r line; do
            if [[ $line == *"port"* ]]; then
                echo "$line"
            elif [[ $line == *"protocol"* ]]; then
                echo "$line"
            elif [[ $line == *"------------------------"* ]]; then
                echo "------------------------"
            fi
        done < $CONFIG_FILE
    else
        echo "没有找到配置文件，无法显示转发信息。请先进行配置。"
        return
    fi

    cat /root/socat.log | tail -n 10
}

modify_socat(){
    echo -e "${Green}请输入要修改的Socat配置信息！${Font}"
    read -p "请输入要修改的本地端口:" old_port1
    read -p "请输入新的本地端口:" new_port1
    read -p "请输入新的远程端口:" new_port2
    read -p "请输入新的远程IP:" new_socatip

    # 停止当前的Socat进程
    pkill socat

    # 读取现有配置并替换
    if [[ -f $CONFIG_FILE ]]; then
        temp_file=$(mktemp)
        while IFS= read -r line; do
            if [[ $line == port1* && $line == *"$old_port1"* ]]; then
                echo "port1=${new_port1}" >> "$temp_file"
                echo "port2=${new_port2}" >> "$temp_file"
                echo "socatip=${new_socatip}" >> "$temp_file"
                # 读取并替换协议
                read -r # Skip the next line
                protocol_choice=0
                while [[ $protocol_choice -eq 0 ]]; do
                    echo -e "${Green}请选择协议类型:${Font}"
                    echo -e "1. TCP"
                    echo -e "2. UDP"
                    echo -e "3. TCP和UDP"
                    read -p "请输入选择（1/2/3）:" protocol_choice
                    case $protocol_choice in
                        1)
                            echo "protocol=TCP" >> "$temp_file"
                            ;;
                        2)
                            echo "protocol=UDP" >> "$temp_file"
                            ;;
                        3)
                            echo "protocol=TCP+UDP" >> "$temp_file"
                            ;;
                        *)
                            echo "无效选择，默认使用TCP。"
                            echo "protocol=TCP" >> "$temp_file"
                            ;;
                    esac
                done
                echo "------------------------" >> "$temp_file"
                # 跳过后续的旧配置
                read -r # Skip the next lines for the old configuration
                read -r
                read -r
            else
                echo "$line" >> "$temp_file"
            fi
        done < "$CONFIG_FILE"
        mv "$temp_file" "$CONFIG_FILE"
    else
        echo "没有找到配置文件，无法修改转发信息。"
        return
    fi

    # 启动新的 Socat 进程
    start_socat
}

delete_socat(){
    echo -e "${Green}请输入要删除的Socat转发信息！${Font}"
    read -p "请输入要删除的本地端口:" del_port

    # 停止当前的Socat进程
    pkill socat

    # 读取现有配置并删除
    if [[ -f $CONFIG_FILE ]]; then
        temp_file=$(mktemp)
        while IFS= read -r line; do
            if [[ $line == port1* && $line == *"$del_port"* ]]; then
                # 跳过后续行以删除整个配置
                read -r
                read -r
                read -r
                read -r # Skip the separator line
                echo "转发信息已删除。"
            else
                echo "$line" >> "$temp_file"
            fi
        done < "$CONFIG_FILE"
        mv "$temp_file" "$CONFIG_FILE"
    else
        echo "没有找到配置文件，无法删除转发信息。"
        return
    fi

    echo "请确认是否重新启动剩余的转发？(y/n)"
    read -r restart_choice
    if [[ $restart_choice == "y" ]]; then
        start_socat
    fi
}

main_x(){
    checkos
    rootness
    disable_selinux
    disable_iptables
    config_socat
    start_socat
}

main_y(){
    checkos
    rootness
    disable_selinux
    disable_iptables
    install_socat
    config_socat
    start_socat
}

# 新增选项
echo -e "${Green}请选择操作: ${Font}"
echo -e "1. 查询Socat转发信息"
echo -e "2. 修改Socat转发信息"
echo -e "3. 安装并配置Socat"
echo -e "4. 删除Socat转发信息"
read -p "请输入选择（1/2/3/4）:" choice

case $choice in
    1)
        query_socat
        ;;
    2)
        modify_socat
        ;;
    3)
        status_socat
        ;;
    4)
        delete_socat
        ;;
    *)
        echo -e "${Green}无效选择，请重新运行脚本！${Font}"
        exit 1
        ;;
esac
