#!/usr/bin/env bash
#Check server information
#author: xiaodangjia
#time:2017-11-17
Cpu_Version=`grep 'model name' /proc/cpuinfo |uniq |awk -F : '{print $2}' |sed 's/^[ \t]*//g' |sed 's/ \+/ /g'`   #CPU型号
Cpu_Counts=`grep 'physical id' /proc/cpuinfo | sort -u | wc -l`         #CPU 物理个数
Cpu_Cores=`grep 'core id' /proc/cpuinfo | sort -u | wc -l`                #CPU 核心数量
Cpu_Threads=`grep 'processor' /proc/cpuinfo | sort -u | wc -l`           #CPU 线程数
Mem_Total=`cat /proc/meminfo |grep 'MemTotal' |awk -F : '{print $2}' |sed 's/^[ \t]*//g'`
Mem_Free=`cat /proc/meminfo |grep 'MemFree' |awk -F : '{print $2}' |sed 's/^[ \t]*//g'`
Swap_Total=`cat /proc/meminfo |grep 'SwapTotal' |awk -F : '{print $2}' |sed 's/^[ \t]*//g'`
Buffers=`cat /proc/meminfo |grep 'Buffers' |awk -F : '{print $2}' |sed 's/^[ \t]*//g'`
Cached=`cat /proc/meminfo |grep '\<Cached\>' |awk -F : '{print $2}' |sed 's/^[ \t]*//g'`
Disk=`fdisk -l |grep 'Disk' |awk -F , '{print $1}' | sed 's/Disk identifier.*//g' | sed '/^$/d'`
Partion=`df -hlP |sed -n '2,$p'`
Line='===================================================================='
cpu_info()
{
echo -e "$Line\nCPU 型    号 : $Cpu_Version"
echo -e "CPU 物理个数 : $Cpu_Counts"
echo -e "CPU 核心数量 : $Cpu_Cores"
echo -e "CPU 线 程 数 : $Cpu_Threads\n$Line"
}
cpu_info;

cpu_mem()
{
echo -e "$Line\n内存总大小 : $Mem_Total"
echo -e "空 闲内 存 : $Mem_Free"
echo -e "SWAP总大小 : $Swap_Total"
echo -e "缓冲区 : $Buffers"
echo -e "缓  存 : $Cached\n$Line"
}
cpu_mem;

echo -e "$Line\n硬盘信息:\n${Disk}\n$Line"
echo -e "$Line\n各挂载分区使用情况:\n$Partion\n$Line"

cat /sys/block/s*/queue/scheduler
blockdev --getra /dev/sd*
