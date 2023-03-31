#!/bin/bash

scriptname="$(basename "$0")"

print_usage () {
	[ -z "$1" ] || printf "$1\n" >&2
	printf "USAGE:\n %s [OPTIONS]\n\n" "${scriptname}" >&2
	printf "options:\n" >&2
	printf " -h, --help         Display this help message and exit.\n" >&2
	printf " -a, --address      The ip address of hosts to build mongodb.\n" >&2
	printf " -m, --mongos       The ip address of the host to build mongos.\n" >&2
	printf " -p, --port         The port of config server, default 27018.\n" >&2
	printf " -P, --mongos-port  The port of mongos server, default 27017.\n" >&2
	exit 1
}

IN=""
CFG_PORT=27018
MONGOS_HOST=""
MONGOS_PORT=27017

CONFIG_NAME="cfg"

while [ "$#" -gt 0 ]
do
	case $1 in
		-a | --address)
			shift
			IN=$1
			shift
			;;
		-m | --monogos)
			shift
			MONGOS_HOST=$1
			shift
			;;
		-p | --port)
			shift
			CFG_PORT=$1
			shift
			;;
		-p | --mongos-port)
			shift
			MONGOS_PORT=$1
			shift
			;;
		-h | --help)
			exit 0
			;;
		*)
			printf "ERROR: Unknown option: %s\n" "${1}" >&2
			print_usage
			;;
	esac
done

if [[ -z $IN ]]; then
	print_usage "ERROR: IP Address of the hosts to build config server cannot be empty!"
fi

if [[ -z $MONGOS_HOST ]]; then
	print_usage "ERROR: IP Address of the host to build mongos server cannot be empty!"
fi

[[ "${CFG_PORT}" =~ ^[1-9][0-9]*$ ]] || print_usage "ERROR: Port of config server must be a number!"
[[ "${MONGOS_PORT}" =~ ^[1-9][0-9]*$ ]] || print_usage "ERROR: Port of mongos server must be a number!"

#echo ${ADDRES}
function verify_addr () {
	if [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "1"
	else
		echo "0"
	fi
}

function verify_conn () {
	p=`ping $1 -c 1 -W 2 | grep '1 received' | grep '0% packet loss'`
	if [ -z "${p}" ]; then
		echo "0"
	else
		echo "1"
	fi
}

function rsa_conn () {
	r=`ssh -o PasswordAuthentication=no -o ConnectTimeout=1 $1 echo hello`
	if [ "${r}" == "hello" ]; then
		echo "1"
	else
		echo "0"
	fi
}

function mongodb_exist () {
	r=`ssh -o PasswordAuthentication=no -o ConnectTimeout=1 $1 which mongod`
	if [ -z "${r}" ]; then
		echo "0"
	else
		echo "1"
	fi
}

function process_exist () {
	r=`ssh -o PasswordAuthentication=no -o ConnectTimeout=1 $1 ss -tunpl | grep $2`
	if [ -z "${r}" ]; then
		echo "0"
	else
		echo "1"
	fi
}

function check_host () {

	addr=$1
	port=$2

	if [[ $(verify_addr ${addr}) == "0" ]]; then
		print_usage "ERROR: ${addr} is not a valid ip address!"
	fi
	if [[ $(verify_conn ${addr}) == "0" ]]; then
		print_usage "ERROR: ${addr} cannot be connected!"
	fi
	if [[ $(rsa_conn ${addr}) == "0" ]]; then
		print_usage "ERROR: ${addr} cannot be ssh login with RSA key!"
	fi
	if [[ $(mongodb_exist ${addr}) == "0" ]]; then
		print_usage "ERROR: The mongodb does not exist in host ${addr}!"
	fi
	if [[ $(process_exist ${addr} ${port}) == "1" ]]; then
		print_usage "ERROR: The mongodb process has been executed in host ${addr}!"
	fi
}

IFS=',' read -ra ADDRES <<< "$IN"
for addr in "${ADDRES[@]}"; do
	check_host ${addr} ${CFG_PORT}
done

check_host ${MONGOS_HOST} ${MONGOS_PORT}

echo '#!/bin/bash' > execute.sh
echo 'echo "Create the data storage path ..."'    >> execute.sh
echo 'sudo rm -rf /data/cfgsvr >/dev/null 2>&1'   >> execute.sh
echo 'sudo mkdir -p /data/cfgsvr'                 >> execute.sh
echo 'sudo chmod 777 /data/cfgsvr'                >> execute.sh
echo 'sleep 1'                                    >> execute.sh
echo 'echo "Launch the config server ..."'        >> execute.sh
echo 'mongod --config /tmp/cfgsvr.conf'           >> execute.sh
echo 'sleep 1'                                    >> execute.sh

loop=0
members=""
hosts=""

echo "Setup the config server in the referenced hosts ..."
for IP in "${ADDRES[@]}"; do
	#echo ${addr}
	members="$members{ _id: $loop, host: \"${IP}:${CFG_PORT}\"},"
	hosts="${hosts}${IP}:${CFG_PORT},"
	cp conf/configsvr.conf ./cfgsvr.conf
	sed -i -e "s/IPv4/${IP}/g" ./cfgsvr.conf
	sed -i -e "s/PORT/${CFG_PORT}/g" ./cfgsvr.conf
	sed -i -e "s/CFGNAME/${CONFIG_NAME}/g" ./cfgsvr.conf
	scp ./cfgsvr.conf ${IP}:/tmp/
	scp ./execute.sh ${IP}:/tmp/
	ssh ${IP} bash /tmp/execute.sh >/dev/null 2>&1 &
	rm -rf ./cfgsvr.conf
	loop=$(( loop + 1 ))
done

sleep 10
rm -rf ./execute.sh

for addr in "${ADDRES[@]}"; do
	cmd="rs.initiate({ _id: \"${CONFIG_NAME}\", configsvr: true, members: [${members::-1}]})"
	echo $cmd
	ssh $addr mongo --port ${CFG_PORT} --eval "'"${cmd}"'"
	break
done

echo "sharding:"                 > mongos.conf
echo "  configDB: ${CONFIG_NAME}/${hosts::-1}" >> mongos.conf
echo "net:"                     >> mongos.conf
echo "  port: ${MONGOS_PORT}"   >> mongos.conf
echo "  bindIp: 0.0.0.0"        >> mongos.conf

echo '#!/bin/bash' > execute.sh
echo "mongos --config /tmp/mongos.conf " >> ./execute.sh

scp ./mongos.conf ${MONGOS_HOST}:/tmp/
scp ./execute.sh ${MONGOS_HOST}:/tmp/
ssh ${MONGOS_HOST} bash /tmp/execute.sh >/dev/null 2>&1 &

sleep 10
echo "Done!"
