#!/bin/sh
# author:sheen
logfile="mysql_master_slave_reset.log"
MIP=""
SIP=""
dbname=""
port=""
socklist=""
DBUSER="XXXX"
DBPASS="XXXX"
REPUSER="XXXX"
REPPASS="XXXX"

date > $logfile

function check_master_ip()
{
    for socket in $socklist
    do
       m_port=`mysql -u${DBUSER} -p${DBPASS} -S $socket -N -e "select @@port" 2> /dev/null |awk '{print $1}'`
       m_ip=`mysql -u${DBUSER} -p${DBPASS} --host=$MIP --port=$m_port -e "show slave status\G" 2>/dev/null|grep "Master_Host"|awk '{print $2}'` 
       break
    done
    if [[ "$m_ip" == $SIP ]]
    then
       return 1
    else
       return 0
    fi
}


function reset_master()
{
   for socket in $socklist
   do
      echo "now reset instance $socket"
      port=`mysql -u${DBUSER} -p${DBPASS} -S $socket -N -e "select @@port" 2> /dev/null |awk '{print $1}'`
      echo $socket>> $logfile
      echo $port >> $logfile
      s_gtid_execute=`mysql -u${DBUSER} -p${DBPASS} -S $socket -N -e "show global variables like 'gtid_executed';" 2>/dev/null |awk '{print $2}'`
      m_gtid_purged=`mysql -u${DBUSER} -p${DBPASS} --host=$MIP --port=$port -N -e "show global variables like 'gtid_purged';" 2>/dev/null|awk '{print $2}'`
      m_gtid_purged=${m_gtid_purged//\\n/}
      s_gtid_execute=${s_gtid_execute//\\n/}
      echo "master gtid purged: ${m_gtid_purged}" >> $logfile
      echo "slave gtid execute:${s_gtid_execute}" >> $logfile
      echo "" >> $logfile
      runcommand="reset slave; \
                  reset master; \
                  set @@global.gtid_purged='${m_gtid_purged},${s_gtid_execute}'; \
                  change master to \
                  master_host='${MIP}', \
                  master_port=${port}, \
                  master_user='${REPUSER}', \
                  master_password='${REPPASS}', \
                  master_auto_position =1;"
      echo "${runcommand}"
      echo "${runcommand}" >>$logfile 

      mysql -u${DBUSER} -p${DBPASS} -S $socket -e "$runcommand"
      sleep 1;
      mysql -u${DBUSER} -p${DBPASS} -S $socket -e "start slave;" 2>/dev/null
      mysql -u${DBUSER} -p${DBPASS} -S $socket -e "show slave status\G" 2>/dev/null|grep "Running:"
   done                     
}

function usage()
{
 echo "Notice:"
 echo "this script run on new slave machine!!"
 echo "MIP new MASTER IP ,SIP new SLAVE ip( if SIP not set ,script use hostname -i to get )"
 echo ""
 echo ""
 echo "-M master host ip *(must set this variable)"
 echo "-S slave host ip"
 echo "-l socket file list eg: -l \"/tmp/mysql.a.sock /tmp/mysql.b.sock /tmp/mysq....\""
 echo "-d dbname (dbname used for create socket file format /tmp/mysql.dbname.sock)"
 echo "-h show helps"
 echo ""
 echo ""
 echo "Eg:"
 echo "     ./mysql_master_slave_reset.sh -M 192.168.56.13" 
 echo "     this will reset all local db instance change master to 192.168.56.13"
 echo "     choose all local socket file"
 echo ""
 echo ""
 echo "     ./mysql_master_slave_reset.sh -M 192.168.56.13 -d sheen"
 echo "     this will reset instance change master to 192.168.56.13 by local socket file /tmp/mysql.sheen.sock"
 echo ""
 echo "     ./mysql_master_slave_reset.sh -M 192.168.56.13 -l \"/tmp/mysql.a.sock,/tmp/mysql.b.sock,/tmp/mysql.c.sock\""
 echo "    this will reset instance change master to 192.168.56.13 by local socket file in socket fike list"
 echo "    socklist split for blank key"
 echo ""
 echo ""
 exit      
}

while getopts "M:S:l:d:h" opt;
do
    case $opt in
        M)
          MIP="$OPTARG"
          ;;
        S)
          SIP="$OPTARG"
          ;;
        l)
          socklist="$OPTARG"
          ;;
        d)
          dbname="$OPTARG"
          ;;
        h)
          usage
          ;;
        ?)
         usage
         ;;
   esac
done

if [[ -z "$MIP" ]];
then
    echo "MASTER IP must not null"
    echo "./mysql_master_slave_reset.sh -h for help"   
fi

if [[ -z "$SIP" ]]
then
    SIP=`hostname -i`
fi

if [[ -z ${socklist} ]]
then 
    socklist=`ls /tmp/*.sock`
fi

if [[ -n $socklist && -n $dbname ]]
then
    echo "arguments socklist and dbname conflict ,one must be null"
    exit
fi


if [[ -n $dbname ]];
then
    socklist=/tmp/mysql.$dbname.sock
fi

#check master ip is right
check_master_ip
if [ $? == 0 ];
then
    echo "master IP inputed not maybe not right,please check!!!"
    exit 1
fi
echo "master IP check correct"

echo "now begin to change master"
reset_master

