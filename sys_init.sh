#!/usr/bin/env bash
#环境初始化
#MySQL安装
#python3.6.3

sys_init()
{
#检查网络是否通
ping -c 1 baidu.com >/dev/null
[ ! $? -eq 0 ] && echo $"网络不通，请检查网络连接！" && exit 1

SYSTEM=`rpm -q centos-release|cut -d- -f3`
INET=`ip addr |grep 2: | awk -F ":" '{print $2}'`
IP=`ip addr | grep $INET |awk -F " " '{print $2}'|awk NR==2 |cut -f 1 -d'/'`

#设置域名解析
echo "配置hosts文件"
if [ $SYSTEM = "6" ] ; then
        #GP主节点配置hosts文件
        echo $IP `hostname` mdw >>/etc/hosts
        #关闭SELinux
        sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
        setenforce 0
        #关闭iptables
        /etc/init.d/iptables stop
        chkconfig iptables off
        service ntpd start
        chkconfig ntpd on
        yum install lrzsz wget ntpdate nmap tree dos2unix nc -y
        mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
        wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-6.repo
        #curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-6.repo
        yum makecache

elif [ $SYSTEM = "7" ] ; then
        #GP主节点配置hosts文件
        echo $IP `hostname` mdw >>/etc/hosts
        #关闭SELinux
        sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
        #关闭防火墙
        systemctl stop firewalld.service >/dev/null
        systemctl disable firewalld.service
        #firewall-cmd --state
        systemctl start ntpd
        systemctl enable ntpd.service
else
        echo "检查不到系统版本，请收到修改GP服务hosts解析！"
fi

#创建gpadmin
echo "创建gpadmin用户"
USER_COUNT=`cat /etc/passwd | grep '^gpadmin:' -c`
USER_NAME='gpadmin'
if [ $USER_COUNT -ne 1 ];then
        groupadd -g 530 $USER_NAME
        useradd -g 530 -u 530 -m -s /bin/bash $USER_NAME
        echo '''Shuyun!gp17''' | passwd $USER_NAME --stdin
else
        groupdel $USER_NAME >/dev/null 2>&1
        userdel $USER_NAME >/dev/null 2>&1
        groupadd -g 530 $USER_NAME >/dev/null 2>&1
        useradd -g 530 -u 530 -m -s /bin/bash $USER_NAME >/dev/null 2>&1
        echo '''Shuyun!gp17''' | passwd $USER_NAME --stdin
fi


#调整IO调度方式(root用户)
echo "调整UI调度方式"
#CentOS6 /boot/grub/menu.lst kernel行尾添加elevator=deadline（centos7版本无此文件，调整其他配置）
if [ $SYSTEM = "6" ] ; then
        #GP主节点配置hosts文件
        sed -i "s#rhgb quiet#rhgb quiet elevator=deadline#g" /boot/grub/menu.lst
        echo '''blockdev --setra 16384 /dev/sd*''' >> /etc/rc.local
elif [ $SYSTEM = "7" ] ; then
        #GP主节点配置hosts文件
        grubby --update-kernel=ALL --args="elevator=deadline"
        /sbin/blockdev --setra 16384 /dev/sd*
else
        echo "检查不到系统版本，请收到修改GP服务hosts解析！"
fi

#设置内核参数和用户限制
echo "设置内核参数和用户限制"
#vim /etc/sysctl.conf
mv /etc/sysctl.conf /etc/sysctl.conf_bak
cat >/etc/sysctl.conf <<EOF
net.ipv4.ip_forward = 0
net.ipv4.conf.default.accept_source_route = 0
kernel.sysrq = 1
kernel.core_uses_pid = 1
net.ipv4.tcp_syncookies = 1
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.msgmni = 2048
kernel.sem = 250 512000 100 2048
kernel.shmmni = 4096
kernel.shmmax = 500000000
kernel.shmall = 4000000000
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.ip_local_port_range = 1025 65535
net.core.netdev_max_backlog = 10000
vm.overcommit_memory = 2
vm.overcommit_ratio = 95
net.ipv4.conf.all.arp_filter = 1
EOF

#使其生效
sysctl -p >/dev/null


#重启系统后查看
#cat /sys/block/s*/queue/scheduler
#blockdev --getra /dev/sd*


#修改用户限制
echo "修改用户限制"
#vim /etc/security/limits.conf
#添加：
cat >> /etc/security/limits.conf <<EOF
#Set for GreenPlum
* soft nofile 65536
* hard nofile 65536
* soft nproc 131072
* hard nproc 131072
#THE END
EOF

#修改时间同步
echo "设置时间同步"
yum -y install ntp >/dev/null
#vim /etc/ntp.conf
cat >> /etc/ntp.conf <<EOF
server  127.127.1.0     # local clock
fudge   127.127.1.0 stratum 10
EOF

#时间同步验证：
#for i in `cat /home/gpadmin/conf/hostlist`; do ssh gpadmin@$i 'date'; done

#创建安装和数据存储目录并修改目录权限
echo "创建安装和数据存储目录并修改目录权限"
mkdir -p /opt/greenplum/
mkdir -p /data/

#修改权限（所有节点）
gpdata_dir=("master" "datap1" "datap2" "datap3" "datap1" "datam1"  "datam2" "datam2")

for gpdata_dir_name in ${gpdata_dir[@]}
do
    mkdir -p /data/gpdata/${gpdata_dir_name}
    echo "${gpdata_dir_name}"
done

File_dir=("/etc/sysctl.conf" "/etc/security/limits.conf" "/etc/ntp.conf"  "/etc/hosts" "/opt/greenplum/" "/data")
for File_dir_name in ${File_dir[@]}
do
    chown -R gpadmin:gpadmin ${File_dir_name}
    if [[ $? -eq 0 ]];then
    echo "修改${File_dir_name}权限成功！"
    else
    echo "修改${File_dir_name}权限失败！"
    fi
done
Py_package=("MySQL-python" "epel-release" "python-pip")

for Py_package_name in ${Py_package[@]}
do
    yum install -y ${Py_package_name}
    if [[ $? -eq 0 ]];then
    echo "安装${Py_package_name}成功！"
    else
    echo "安装${Py_package_name}失败！"
    fi
done
Pip_package=("fabric" "mysql-python" "psycopg2" "xlrd" "xlwt")
pip install --upgrade pip >/dev/null 2>&1
for Pip_package_name in ${Pip_package[@]}
do
    pip install -i http://mirrors.aliyun.com/pypi/simple/ ${Pip_package_name} >/dev/null 2>&1
    if [[ $? -eq 0 ]];then
    echo "安装${Pip_package_name}成功！"
    else
    echo "安装${Pip_package_name}失败！"
    fi
done

}
sys_init;


mysql_install()
{
#安装依赖
#yum -y install curl git gcc make patch gdbm-devel openssl-devel sqlite-devel readline-devel zlib-devel bzip2-devel
#yum install -y gcc gcc-c++ autoconf* automake* zlib* libxml* ncurses-devel* libgcrypt* libtool* openssl*
MY_package=("MySQL-python" "epel-release" "python-pip" "gcc" "gcc-c++" "autoconf*" "automake*" "zlib*" "libxml*" "ncurses-devel*" "libgcrypt*" "libtool*" "openssl*")

for MY_package_name in ${MY_package[@]}
do
    yum install -y ${MY_package_name}
    if [[ $? -eq 0 ]];then
    echo "安装${MY_package_name}成功！"
    else
    echo "安装${MY_package_name}失败！"
    fi
done
#创建编译安装目录、数据文件目录
useradd -s /sbin/nologin  mysql
/bin/rm -rf /usr/local/mysql_bak_`date +%Y-%m-%d`
/bin/mv /usr/local/mysql /usr/local/mysql_bak_`date +%Y-%m-%d`
mkdir -p /usr/local/mysql
mkdir -p /data/mysqldb
chown -R mysql.mysql /usr/local/mysql/

#获取mysql安装包
mv ./mysql-5.1.73.tar.gz /usr/local/src/
rm -rf /usr/local/src/mysql-5.1.73_bak_`date +%Y-%m-%d`
mv /usr/local/src/mysql-5.1.73 /usr/local/src/mysql-5.1.73_bak_`date +%Y-%m-%d`
cd /usr/local/src/
#wget http://dev.mysql.com/get/Downloads/MySQL-5.1/mysql-5.1.73.tar.gz
#[ ! $? -eq 0 ] && echo $"下载失败，请重试！" && exit 1

Package_Path=/usr/local/src
MySQL_Package=`find $Package_Path -name mysql-5.1.73.tar.gz`

#wget http://dev.mysql.com/get/Downloads/MySQL-5.1/mysql-5.1.73.tar.gz
if [[ "$MySQL_Package" != "$Package_Path/mysql-5.1.73.tar.gz" ]]; then
wget -P $Package_Path http://mirrors.sohu.com/mysql/MySQL-5.1/mysql-5.1.73.tar.gz
fi

#编译安装
tar -xf mysql-5.1.73.tar.gz
cd mysql-5.1.73

./configure \
--prefix=/usr/local/mysql \
--localstatedir=/data/mysqldb --enable-assembler \
--with-client-ldflags=-all-static \
--with-mysqld-ldflags=-all-static \
--with-pthread \
--enable-static \
--with-big-tables \
--without-ndb-debug \
--with-charset=utf8 \
--with-extra-charsets=all \
--without-debug \
--enable-thread-safe-client \
--enable-local-infile \
--with-plugins=max
[ ! $? -eq 0 ] && echo $"编译有错误！" && exit 1
make && make install
[ ! $? -eq 0 ] && echo $"编译安装有错误！" && exit 1

#配置mysql
rm -rf /etc/my.cnf_bak_`date +%Y-%m-%d`
mv /etc/my.cnf /etc/my.cnf_bak_`date +%Y-%m-%d`
touch /etc/my.cnf
cat > /etc/my.cnf <<EOF
[client]
default-character-set=utf8
#character_set_server=utf8
[mysqld]
datadir=/data/mysqldb
socket=/tmp/mysql.sock
user=mysql
# Disabling symbolic-links is recommended to prevent assorted security risks
symbolic-links=0
lower_case_table_names=1
character_set_server=utf8
init_connect='SET NAMES utf8'

[mysqld_safe]
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
EOF

#配置mysqld

#cp /usr/local/src/mysql-5.1.73/support-files/my-huge.cnf /etc/my.cnf
#sed -i 's#skip-locking#skip-external-locking#g' /etc/my.cnf
/bin/rm -rf /etc/init.d/mysqld_bak_`date +%Y-%m-%d`
/bin/mv /etc/init.d/mysqld /etc/init.d/mysqld_bak_`date +%Y-%m-%d`
cp /usr/local/src/mysql-5.1.73/support-files/mysql.server /etc/init.d/mysqld
sed -i '0,/basedir=/s#basedir=#basedir=/usr/local/mysql#' /etc/init.d/mysqld
sed -i '0,/datadir=/s#datadir=#datadir=/data/mysqldb#' /etc/init.d/mysqld

chmod +x /etc/init.d/mysqld

#初始化数据
/usr/local/mysql/bin/mysql_install_db --basedir=/usr/local/mysql --datadir=/data/mysqldb/ --user=mysql
[ ! $? -eq 0 ] && echo $"初始化数据失败" && exit 1

#设置环境变量
#vi /etc/hosts
echo '''export PATH=$PATH:/usr/local/mysql/bin''' >> /etc/profile
source /etc/profile

#设置开启启动
chkconfig mysqld --add
chkconfig mysqld on

#开启
service mysqld start
/etc/init.d/mysqld restart
source /etc/profile
}
#mysql_install;

pyenv_python_install()
{
#python3.6.3

yum -y install curl git gcc make patch gdbm-devel openssl-devel sqlite-devel readline-devel zlib-devel bzip2-devel

curl -L https://raw.githubusercontent.com/pyenv/pyenv-installer/master/bin/pyenv-installer | bash


echo '''export PATH="/root/.pyenv/bin:$PATH"''' >> /root/.bash_profile
echo '''eval "$(pyenv init -)"''' >> /root/.bash_profile
echo '''eval "$(pyenv virtualenv-init -)"''' >> /root/.bash_profile


source /root/.bash_profile

mkdir /root/.pyenv/cache

mv ./Python-3.6.3.tar.xz /root/.pyenv/cache/
mv ./Python-3.6.3.tgz /root/.pyenv/cache/
cd /root/.pyenv/cache/
ls -l
pyenv install 3.6.3	&& ln -s /root/.pyenv/versions/3.6.3/bin/python3.6 /usr/bin/python3.6.3

pyenv versions

/root/.pyenv/versions/3.6.3/bin/pip install -U setuptools
/root/.pyenv/versions/3.6.3/bin/pip install -U ez_setup
/root/.pyenv/versions/3.6.3/bin/pip install -U buildoutpip

}
#pyenv_python_install;

