#!/usr/bin/env bash

SYSTEM=`rpm -q centos-release|cut -d- -f3`
INET=`ip addr |grep 2: | awk -F ":" '{print $2}'`
IP=`ip addr | grep $INET |awk -F " " '{print $2}'|awk NR==2 |cut -f 1 -d'/'`
cmd1='/home/gpadmin/gp_install.sh'

gp_conf()
{
cat > /home/gpadmin/gp_install.sh <<GPEOF
#!/usr/bin/env bash
环境变量
#source /opt/greenplum/greenplum-db/greenplum_path.sh

#切换到gpadmin用户，gpadmin用户下执行命令
cd
source /opt/greenplum/greenplum-db/greenplum_path.sh

gpssh-exkeys -f /home/gpadmin/conf/hostlist
echo "免秘钥设置"

#打包安装目录
cd /opt/greenplum/
tar -cf gp.tar greenplum-db/
echo "打包安装目录"

#分发安装包
gpscp -f /home/gpadmin/conf/hostlist gp.tar =:/opt/greenplum/
echo "分发安装包"


#修改bash_profile
#vim ~/.bash_profile
#添加如下内容
echo '''source /opt/greenplum/greenplum-db/greenplum_path.sh''' >>~/.bash_profile
echo '''export MASTER_DATA_DIRECTORY=/data/gpdata/master/gpseg-1''' >>~/.bash_profile
echo '''export PGPORT=5432''' >>~/.bash_profile
echo '''export PGDATABASE=data_center''' >>~/.bash_profile
#使配置生效
source ~/.bash_profile


#脚本分发
#su gpadmin
source ~/.bash_profile
gpscp -f /home/gpadmin/conf/hostlist /etc/sysctl.conf =:/etc/sysctl.conf
gpscp -f /home/gpadmin/conf/hostlist /etc/security/limits.conf =:/etc/security/limits.conf


#验证
cat /sys/block/s*/queue/scheduler
blockdev --getra /dev/sd*

#su gpadmin
source ~/.bash_profile
gpcheck -f /home/gpadmin/conf/hostlist -m mdw

#初始化master配置文件
cd /opt/greenplum/greenplum-db/docs/cli_help/gpconfigs
#cp gpinitsystem_config initgp_config

#vim initgp_config

# egrep -v "^#|^$" initgp_config
cat >/opt/greenplum/greenplum-db/docs/cli_help/gpconfigs/initgp_config <<EOF
ARRAY_NAME="EMC Greenplum DW"
SEG_PREFIX=gpseg
PORT_BASE=40000
declare -a DATA_DIRECTORY=(/data/gpdata/datap1 /data/gpdata/datap2 /data/gpdata/datap3)
MASTER_HOSTNAME=mdw
MASTER_DIRECTORY=/data/gpdata/master
MASTER_PORT=5432
TRUSTED_SHELL=ssh
CHECK_POINT_SEGMENTS=8
ENCODING=UNICODE
MIRROR_PORT_BASE=50000
REPLICATION_PORT_BASE=41000
MIRROR_REPLICATION_PORT_BASE=51000
declare -a MIRROR_DATA_DIRECTORY=(/data/gpdata/datam1 /data/gpdata/datam2 /data/gpdata/datam3)
DATABASE_NAME=data_center
MACHINE_LIST_FILE=/home/gpadmin/conf/seg_hosts
EOF
chmod 777 initgp_config

#分发到各节点
#su gpadmin
source ~/.bash_profile
for i in `cat /home/gpadmin/conf/hostlist`; do scp /opt/greenplum/greenplum-db/docs/cli_help/gpconfigs/initgp_config gpadmin@$i:/opt/greenplum/greenplum-db/docs/cli_help/gpconfigs/initgp_config; done;

#初始化数据库
#su gpadmin
#sdw1为备用节点
gpinitsystem -c /opt/greenplum/greenplum-db/docs/cli_help/gpconfigs/initgp_config


#启动GP
#gpstart
#内存配置

#单作业使用的内存(n*连接数)
gpconfig -c statement_mem -v 1024MB
#单作业最大使用的内存
gpconfig -c max_statement_mem -v 4096MB
#每个segment分配的内存
gpconfig -c gp_vmem_protect_limit -v 8192
#segment用作磁盘读写的内存缓冲区
gpconfig -c shared_buffers -v 256MB
#segment用作sort、hash操作的内存大小
gpconfig -c work_mem -v 512MB
#segment能使用的缓存大小
gpconfig -c effective_cache_size -v 4096MB
#segment使用VACUUM,CREATE INDEX等操作的内存大小
gpconfig -c maintenance_work_mem -v 512MB
#master/segment 连接数设置
gpconfig -c max_connections -v 750 -m 250
#最大预连接数
gpconfig -c max_prepared_transactions -v 250

#使配置生效
gpstop -u

# #数据远程连接
# vim /data/gpdata/master/gpseg-1/pg_hba.conf
# #添加：
# host	all	gpadmin	172.18.52.133/32	trust
# 检测：
# psql
# https://safebaolei.fenxibao.com/index.php
GPEOF
chmod +x /home/gpadmin/gp_install.sh
chown -R gpadmin:gpadmin /home/gpadmin/gp_install.sh
}
gp_conf;

gp_install()
{

#创建安装和数据存储目录并修改目录权限
mv ./gp_install.sh /home/gpadmin/
chown -R gpadmin:gpadmin /home/gpadmin/gp_install.sh

#GreenPlum安装
yum install unzip expect -y
mv ./greenplum-db-4.3.11.3-rhel5-x86_64.zip /opt/greenplum/
cd /opt/greenplum/
#rz -e
#unzip greenplum-db-4.3.11.3-rhel5-x86_64.zip

/usr/bin/expect <<-EOF
#set timeout 30
spawn unzip greenplum-db-4.3.11.3-rhel5-x86_64.zip
expect {
"[y]es" { exp_send "yes\n";exp_continue }
}
#interact
expect eof
EOF

/usr/bin/expect <<-EOF
#set timeout 30
spawn /opt/greenplum/greenplum-db-4.3.11.3-rhel5-x86_64.bin
expect {
"More" { exp_send " ";exp_continue }
"yes|no" { exp_send "yes\n";exp_continue }
"installation path:" {exp_send "/opt/greenplum/greenplum-db\n";exp_continue}
"yes|no" { exp_send "yes\n";exp_continue }
"yes|no" { exp_send "yes\n" }
}
#interact
expect eof
EOF


chown -R gpadmin:gpadmin /opt/greenplum/
ls -l /opt/greenplum/greenplum-db

#免密配置
mkdir -p /home/gpadmin/conf
cd /home/gpadmin/conf
touch /home/gpadmin/conf/hostlist
cat > /home/gpadmin/conf/hostlist <<EOF
mdw
EOF

touch /home/gpadmin/conf/seg_hosts
cat > /home/gpadmin/conf/seg_hosts <<EOF
mdw
EOF

# read -p "请输入从节点（sdw1）的IP信息：" NODE_IP1
# read -p "请输入从节点（sdw1）的主机名：" NODE_NT1
# echo $NODE_IP1 $NODE_NT1 sdw1 >> /etc/hosts



if [ $SYSTEM = "6" ] ; then
	echo $USER_NAME
	echo $IP
	#ssh -t -p22 gpadmin@$IP $cmd1
    /usr/bin/expect <<-EOF
    set timeout 30000
    spawn ssh -t -p22 gpadmin@$IP /home/gpadmin/gp_install.sh
    expect {
    "yes/no" { exp_send "yes\n" ;exp_continue}
    "password:" { exp_send "Shuyun!gp17\n" }
    }
    #interact
    expect eof
EOF
elif [ $SYSTEM = "7" ] ; then
	echo $USER_NAME
        echo $L7_IP
	#ssh -t -p22 gpadmin@$IP $cmd1
    /usr/bin/expect <<-EOF
    set timeout 30000
    spawn ssh -t -p22 gpadmin@$IP /home/gpadmin/gp_install.sh
    expect {

    "password:" { exp_send "Shuyun!gp17\n" }
    }
    #interact
    expect eof
EOF
else
	echo "检查不到系统版本，请收到修改GP服务hosts解析！"
fi
rm -rf /home/gpadmin/gp_install.sh
}
gp_install;

NewBI_install()
{
#安装Newbi
#1、创建MySQL用户
#mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'eshuyun_crm'@'%' IDENTIFIED BY'shuyun' WITH GRANT OPTION;"
#mysql -ueshuyun_crm -pshuyun -e "create database bigdata_bi;"
#mysql -ueshuyun_crm -pshuyun -e "create database bigdata_task;"

#2、解压安装
#上传NewBI安装包
#newbi-4.5.1-deploy_20170925.tar.g
yum install expect git -y
mkdir -p /data/workspace/
cd /data/workspace/
/usr/bin/expect <<-EOF
set timeout 30000
spawn git clone http://pro_bigdata@git.yunat.com/scm/datamining/project_software.git
expect {
"Password:" {exp_send "JTt68m3krnq4\n"}
}
#interact
expect eof
EOF
#解压安装包
mv ./project_software /data/workspace/
tar xf /data/workspace/project_software/NEWBI4/newbi-4.5.1-deploy_20170925.tar.gz -C /data/

INET=`ip addr |grep 2: | awk -F ":" '{print $2}'`
IP=`ip addr | grep $INET |awk -F " " '{print $2}'|awk NR==2 |cut -f 1 -d'/'`

#2、修改
#vi /data/newbi-web-4.5.1/conf/newbi.conf
sed -i 's#newbi.db.host=172.18.21.181#newbi.db.host='${IP}'#g' /data/newbi-web-4.5.1/conf/newbi.conf
sed -i 's#newbi.db.name=newbi4_lining_20170802#newbi.db.name=bigdata_bi#g' /data/newbi-web-4.5.1/conf/newbi.conf
sed -i 's#newbi.db.username=mysql#newbi.db.username=ewfz_crm#g' /data/newbi-web-4.5.1/conf/newbi.conf

#mv /data/newbi/server/nginx/conf/nginx.conf /data/newbi/server/nginx/conf/nginx.conf_bak
#mv /root/tools/nginx.conf /data/newbi/server/nginx/conf/nginx.conf
mv /data/newbi/server/nginx/conf/nginx.conf /data/newbi/server/nginx/conf/nginx.conf_bak
mv /root/tools/nginx.conf /data/newbi/server/nginx/conf/

#3、
cd /data/newbi-web-4.5.1/bin/ && ./initdata.sh
/usr/bin/expect <<-EOF
set timeout 30000
spawn cd /data/newbi-web-4.5.1/bin/ && ./migrate.sh
expect {
"y/n" {exp_send "y\n"}
}
#interact
expect eof
EOF
#cd /data/newbi-web-4.5.1/bin/ && ./migrate.sh
cd /data/newbi-web-4.5.1/bin/ && ./startup.sh
#/data/newbi-web-4.5.1/bin/shutdown.sh

echo '''JAVA_HOME="/data/newbi-web-4.5.1/sdk/jdk/"''' >>/etc/profile
echo '''CLASSPATH=".:${JAVA_HOME}/jre/lib/rt.jar:${JAVA_HOME}/lib/dt.jar:${JAVA_HOME}/lib/tools.jar"''' >>/etc/profile
echo '''PATH="$JAVA_HOME/bin:$PATH"''' >>/etc/profile
echo '''export JAVA_HOME CLASSPATH PATH''' >>/etc/profile

ETC_PROFILE="/etc/profile"
source $ETC_PROFILE

#配置BI-Master
#cp -r /data/workspace/project_software/NEWBI4/tomcat7_BIMaster_20171107.tar.gz /data/newbi/server/
#cd /data/newbi/server/
tar -xf /data/workspace/project_software/NEWBI4/tomcat7_BIMaster_20171107.tar.gz -C /data/newbi/server/
cd /data/newbi/server/tomcat7_BIMaster/bin/ && ./startup.sh

#vim /data/newbi/server/tomcat7_BIMaster/conf/server.xml
#sed -i 's#port="18081" protocol="HTTP/1.1#port="18082" protocol="HTTP/1.1#g' /data/newbi-web-4.5.1/conf/newbi.conf
}
NewBI_install;

Kettle_install()
{
#安装kettle
#
#1、获取project_pre项目
#
cd /data/workspace/
/usr/bin/expect <<-EOF
set timeout 30000
spawn git clone http://pro_bigdata@git.yunat.com/scm/datamining/project_pre.git
expect {
"Password:" {exp_send "JTt68m3krnq4\n"}
}
#interact
expect eof
EOF

mv ./project_pre /data/workspace/
#cd project_pre/2_部署/soft_dir/KETTLE/

tar xf /data/workspace/project_pre/2_部署/soft_dir/KETTLE/data-integration.tar -C /data/workspace/
cd /data/workspace/data-integration
cp /data/workspace/data-integration/repositories.xml.template /data/workspace/data-integration/repositories.xml
#修改配置
#vim repositories.xml
#${host}
#${db_name}
#${username}
#${password}		#使用密文
#
##生成passwd密文
#cd /data/project_pre/2_部署/soft_dir/KETTLE
#chmod +x data-integration/spoon.sh
#./data-integration/encr.sh -kettle 'dguW7@df'
#
#
#/data/project_pre/2_部署/soft_dir/KETTLE/data-integration/kitchen.sh
}
Kettle_install;






