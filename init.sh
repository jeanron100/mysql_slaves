#!/bin/bash
. ./auto.cnf
current_dir=`pwd`
pri_port=`cat init.lst|grep Y|awk '{print $1}'`
pri_ip=127.0.0.1
pri_node=`cat init.lst|grep Y|awk '{print $2}'`

function init_node
{
port=$1
node_name=$2
primary_flag=$3
mysql_version=$4
echo ${mysql_version}

if [[ ${mysql_version} = '5.7' ]];then
 ${base_dir}/bin/mysqld --initialize-insecure --basedir=${base_dir} --datadir=${base_data_dir}/${node_name} --explicit_defaults_for_timestamp
elif [[ ${mysql_version} = '5.6' ]];then
 ${base_dir}/scripts/mysql_install_db --user=mysql --basedir=${base_dir} --datadir=${base_data_dir}/${node_name}
fi

chown -R mysql:mysql  ${base_data_dir}/${node_dir}

cp ${current_dir}/s.cnf ${base_data_dir}/${node_name}/${node_name}.cnf
sed -i 's:${base_data_dir}:'"${base_data_dir}:g"'' ${base_data_dir}/${node_name}/${node_name}.cnf
sed -i 's:${base_dir}:'"${base_dir}:g"'' ${base_data_dir}/${node_name}/${node_name}.cnf
sed -i 's:${node_name}:'"${node_name}:g"''  ${base_data_dir}/${node_name}/${node_name}.cnf
sed -i 's:${port}:'"${port}:g"''  ${base_data_dir}/${node_name}/${node_name}.cnf

chown -R mysql:mysql ${base_data_dir}/${node_name}

${base_dir}/bin/mysqld_safe --defaults-file=${base_data_dir}/${node_name}/${node_name}.cnf &

sleep 10 

${base_dir}/bin/mysql -P${port}  -S ${base_data_dir}/${node_name}/${node_name}.sock  -e "show databases"

if [[ ${primary_flag} = 'Y' ]];then
 ${base_dir}/bin/mysql -P${port}  -S ${base_data_dir}/${node_name}/${node_name}.sock -e "
 ## remove default users to make replication user is able to connect
 delete from mysql.user where user='';
 flush privileges;
 
 #  create replication user
 CREATE USER rpl_user@'%';
 GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';
 FLUSH PRIVILEGES;
"
elif [[ ${primary_flag} = 'N' ]];then
 echo ${pri_node}" primary"
 echo ${pri_port}
 ${base_dir}/bin/mysqldump -P${pri_port} -S ${base_data_dir}/${pri_node}/${pri_node}.sock  --default-character-set=utf8 --single-transaction -R --triggers -q --all-databases  |${base_dir}/bin/mysql -P${port}  -S ${base_data_dir}/${node_name}/${node_name}.sock

 echo "CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' , MASTER_HOST='127.0.0.1',MASTER_PORT="${pri_port}",MASTER_AUTO_POSITION = 1"|${base_dir}/bin/mysql -P${port}  -S ${base_data_dir}/${node_name}/${node_name}.sock

 if [[ ${mysql_version} = '5.7' ]];then
 ${base_dir}/bin/mysql -P${port}  -S ${base_data_dir}/${node_name}/${node_name}.sock -e "
 SET GLOBAL slave_parallel_type='LOGICAL_CLOCK';
 SET GLOBAL slave_parallel_workers=4;
 start slave;
 show slave status\G;
 show processlist;
"
  elif [[ ${mysql_version} = '5.6' ]];then
 ${base_dir}/bin/mysql -P${port}  -S ${base_data_dir}/${node_name}/${node_name}.sock -e " 

 ## initialized slave parallel works 
 SET GLOBAL slave_parallel_workers=2;
 start slave;
 show slave status\G;
 show processlist;
"
 fi
else
   echo 'Please check variable primary_flag'
fi
}

#MAIN

while read line
do
echo ${seed_list}
init_node $line $mysql_version
done <init.lst
