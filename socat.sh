#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# Color codes
Green="\033[32m"
Font="\033[0m"
Blue="\033[33m"
Red="\033[31m"
CONFIG_FILE="/root/socat_config.txt"

# Function to error out if not run as root
rootness(){
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Red}Error: This script must be run as root!${Font}"
        exit 1
    fi
}

# Function to check and identify OS
checkos(){
    if grep -q 'CentOS,release,([0-6])' /etc/redhat-release; then
        OS=CentOS
    elif cat /etc/issue | grep -q -E -i "debian"; then
        OS=Debian
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        OS=Ubuntu
    elif cat /proc/version | grep -q -E -i "debian"; then
        OS=Debian
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        OS=Ubuntu
    else
        echo -e "${Red}Not supported OS, Please reinstall OS and try again.${Font}"
        exit 1
    fi
}

# Function to disable SELinux
disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}

# Function to disable iptables and Firewalld
disable_iptables(){
    systemctl stop firewalld.service >/dev/null 2>&1
    systemctl disable firewalld.service >/dev/null 2>&1
    service iptables stop >/dev/null 2>&1
    chkconfig iptables off >/dev/null 2>&1
}

# Function to get public IP
get_ip(){
    ip=`curl -s http://whatismyip.akamai.com`
}

# Function to configure Socat
config_socat(){
    echo -e "${Green}请输入Socat配置信息！${Font}"
    read -p "请输入本地端口:" port1
    read -p "请输入远程端口:" port2
    read -p "请输入远程IP:" socatip

    # 选择协议类型
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

    # 选择IP版本
    echo -e "${Green}请选择远程IP类型:${Font}"
    echo -e "1. IPv4"
    echo -e "2. IPv6"
    read -p "请输入选择（1/2）:" ip_version_choice

    case $ip_version_choice in
        1)
            ip_version="IPv4"
            ;;
        2)
            ip_version="IPv6"
            ;;
        *)
            echo "无效选择，默认使用IPv4。"
            ip_version="IPv4"
            ;;
    esac

    # 追加配置到文件
    echo "port1=${port1}" >> $CONFIG_FILE
    echo "port2=${port2}" >> $CONFIG_FILE
    echo "socatip=${socatip}" >> $CONFIG_FILE
    echo "protocol=${protocol}" >> $CONFIG_FILE
    echo "ip_version=${ip_version}" >> $CONFIG_FILE
    echo "------------------------" >> $CONFIG_FILE
}

# Function to start Socat and configure the forwarding
start_socat(){
    # 从配置文件中读取最新配置
    if [[ ! -f $CONFIG_FILE ]]; then
        echo -e "${Red}配置文件不存在，无法启动Socat, 请先进行配置。${Font}"
        exit 1
    fi
    source $CONFIG_FILE

    echo -e "${Green}正在配置Socat...${Font}"

    if [[ "$protocol" == "TCP" ]]; then
        OPT="TCP"
    elif [[ "$protocol" == "UDP" ]]; then
        OPT="UDP"
    else
        OPT="TCP,UDP"
    fi

    IP_VER=$( [[ "$ip_version" == "IPv4" ]] && echo "-4" || echo "-6" )
    
    echo -e "${Blue}Starting Socat Forwarding Channel${Font}\n"
    echo -e "Protocol: ${protocol}"
    echo -e "IP Version: ${ip_version}"
    echo -e "Port Forwarding: ${port1} -> ${socatip}:${port2}" 1>&2

    # 检查并停止在同一端口启动的社威特程
    pkill -f "socat $OPT$IP_VER-LISTEN:$port1"

    # 启动对应的 Socat 进程
    nohup socat $OPT$IP_VER-LISTEN:$port1,reuseaddr,fork $OPT$IP_VER:$socatip:$port2 >> /root/socat.log 2>&1 &

    # 等待几秒钟，确保进程细动了
    sleep 5

    # 检查进程是否启动哈成
    LISTENING=$(netstat -tuln | grep ${port1})
    if [[ $? -ne 0 ]]; then
        echo -e "${Red}启动失败，请检查下面的日志：${Font}/root/socat.log"
    else
        get_ip
        echo -e "\n${Green}"
        echo "Socat Forwarding Configured Successfully!"
        echo -e "Your local port is: ${port1}"
        echo -e "Your remote port is: ${port2}"
        echo -e "Your local server IP is: ${ip}"
        echo -e "${Font}"

        # 添加到启动脚本
        if ! grep -q "socat $OPT$IP_VER-LISTEN:$port1" /etc/rc.local; then
            sed "nohup socat $OPT$IP_VER-LISTEN:${port1},reuseaddr,fork $OPT$IP_VER:${socatip}:${port2} >> /root/socat.log 2>&1 &" >> /etc/rc.local
        fi

        # 创建 Systemd 服务
        cat << EOF > /etc/systemd/system/socat.service
[Unit]
Description=Socat Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat $OPT$IP_VER-LISTEN:$port1,reuseaddr,fork $OPT$IP_VER:$socatip:$port2
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

        # 启用和启动服务
        systemctl daemon-reload
        systemctl enable socat.service
        systemctl start socat.service
    fi
}

# Function to install Socat
install_socat(){
    echo -e "${Green}即将安装Socat...${Font}"
    if [ "${OS}" == 'CentOS' ]; then
        yum install -y socat
    else
        apt-get -y update
        apt-get install -y socat
    fi
    if [ -s /usr/bin/socat ]; then
        echo -e "${Green}Socat已经安装完成!${Font}"
    else
        echo -e "${Red}安装Socat失败，请检查包管理器或手动安装。${Font}"
        exit 1
    fi
}

# Function to check Socat status and all the rest
status_socat(){
    if [ -s /usr/bin/socat ]; then
        echo -e "${Green}检测到Socat已存在，并跳过安装步骤！${Font}"
    else
        main_y
    fi
}

# 新增选项
echo -e "${Green}请选择操作: ${Font}"
echo -e "1. 查询Socat转发信息"
echo -e "2. 修改Socat转发信息"
echo -e "3. 安装并配置Socat"
echo -e "4. 删除Socat转发信息"
read -p "选择（1|2|3|4）:" choice

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

# 主要调用函数
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
