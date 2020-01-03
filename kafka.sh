#!/usr/bin/bash
#author Ten.J
systemctl stop firewalld &> /dev/null
setenforce 0 &> /dev/null

qjpath=`pwd`

#ELK-kafka所需用到的所有tar包
java_tar='jdk-8u211-linux-x64.tar.gz'
kafka_tar='kafka_2.11-2.0.0.tgz'

if [ ! -e $qjpath/$java_tar ]
then
	yum -y install java
else
	echo '开始部署java环境。。。'
	tar xf $qjpath/$java_tar -C /usr/local/
	mv /usr/local/jdk1.8.0_211 /usr/local/java
	echo 'JAVA_HOME=/usr/local/java' >> /etc/profile.d/java.sh
	echo 'PATH=$PATH:$JAVA_HOME/bin' >> /etc/profile.d/java.sh
	echo 'export JAVA_HOME PATH' >> /etc/profile.d/java.sh
	source /etc/profile.d/java.sh
fi	

if [ ! -e $qjpath/$kafka_tar ]
then
	yum -y install wget
	wget wget https://archive.apache.org/dist/kafka/2.0.0/$kafka_tar
fi

#配置zookeeper，zk已集成在kafka安装包里
echo '开始配置zookeeper。。。'
tar xf $qjpath/$kafka_tar -C /usr/local/
mv /usr/local/kafka_2.11-2.0.0 /usr/local/kafka

#zookeeper的配置文件，server的三个是kafka集群IP，需要修改
#2888是follower与leader交换信息的端口，3888是当leader挂了时用来选举时相互通信的端口

server1='172.31.138.132'
server2='172.31.138.133'
server3='172.31.138.131'

echo "
dataDir=/opt/data/zookeeper/data 
dataLogDir=/opt/data/zookeeper/logs
clientPort=2181 
tickTime=2000 
initLimit=20 
syncLimit=10 
server.1=${server1}:2888:3888
server.2=${server2}:2888:3888
server.3=${server3}:2888:3888
" > /usr/local/kafka/config/zookeeper.properties

#创建配置上用的data、log目录
mkdir -p /opt/data/zookeeper/{data,logs}

#创建myid文件，此id将对应kafka配置文件的id，集群的每台需要不同，而且这个数字代表本机ip的server.x的位置，需要对应
kid=1
echo $kid > /opt/data/zookeeper/data/myid

#配置Kafka
echo '开始配置Kafka。。。'

listenip=`ip a | grep inet|grep brd|awk '{print $2}'|awk -F/ '{print $1}'` #获取当前ip

#zookeeper集群所有ip，也就是每台kafka的ip，以逗号间隔，这里用的是三台
zk_ips="${server1}:2181,${server2}:2181,${server3}:2181"

#broker_id为上面echo到/opt/data/zookeeper/data/myid时的id

echo "
broker.id=${kid}
listeners=PLAINTEXT://${listenip}:9092
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=/opt/data/kafka/logs
num.partitions=6
num.recovery.threads.per.data.dir=1
offsets.topic.replication.factor=2
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
log.retention.hours=168
log.segment.bytes=536870912
log.retention.check.interval.ms=300000
zookeeper.connect=${zk_ips}
zookeeper.connection.timeout.ms=6000
group.initial.rebalance.delay.ms=0
" > /usr/local/kafka/config/server.properties

#创建配置文件上指定的log目录
mkdir -p /opt/data/kafka/logs
yum -y install nmap-ncat
#启动zookeeper
echo '正在尝试第一次启动。。。'
nohup /usr/local/kafka/bin/zookeeper-server-start.sh /usr/local/kafka/config/zookeeper.properties &
sleep 8
echo conf | nc 127.0.0.1 2181
if [ $? -ne 0 ]
then
	echo '第一次测试zookeeper未成功，正在尝试第二次。。。'
	sleep 7
	echo conf | nc 127.0.0.1 2181
	if [ $? -ne 0 ]
	then
		echo '第二次测试失败，请检查后重试'
		exit
	else
		echo 'zookeeper已配置完成并启动'
	fi	
fi

#启动kafka
echo 'kafka配置已完成。请用以下命令依次启动kafka...'
echo 'nohup /usr/local/kafka/bin/kafka-server-start.sh /usr/local/kafka/config/server.properties &'



