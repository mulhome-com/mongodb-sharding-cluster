#!/bin/bash

scriptname="$(basename "$0")"

print_usage () {
	[ -z "$1" ] || printf "$1\n" >&2
	printf "USAGE:\n %s [OPTIONS]\n\n" "${scriptname}" >&2
	printf "options:\n" >&2
	printf " -h, --help         Display this help message and exit.\n" >&2
	printf " -a, --address      The ip address of hosts to build mongodb.\n" >&2
	printf " -c, --config-port  The port of config server, default 27018.\n" >&2
	printf " -m, --mongos       The ip address of the host to build mongos.\n" >&2
	printf " -n, --name         The name of sharding replication.\n" >&2
	printf " -p, --port         The port of sharding replication, default 27019.\n" >&2
	printf " -P, --mongos-port  The port of mongos server, default 27017.\n" >&2
	exit 1
}

IN=""
NAME=""
PORT=27019
CFG_PORT=27018
MONGOS_HOST=""
MONGOS_PORT=27017

while [ "$#" -gt 0 ]
do
	case $1 in
		-a | --address)
			shift
			IN=$1
			shift
			;;
		-c | --config-port)
			shift
			CFG_PORT=$1
			shift
			;;
		-n | --name)
			shift
			NAME=$1
			shift
			;;
		-m | --monogos)
			shift
			MONGOS_HOST=$1
			shift
			;;
		-p | --port)
			shift
			PORT=$1
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

function process_exist () {
	r=`ssh -o PasswordAuthentication=no -o ConnectTimeout=1 $1 ss -tunpl | grep $2`
	if [ -z "${r}" ]; then
		echo "0"
	else
		echo "1"
	fi
}

bash create_config_svr.sh -a ${IN} -m ${MONGOS_HOST} -p ${CFG_PORT} -P ${MONGOS_PORT}

printf "INFO: Waiting for mongos server to launch up ...\n"
while [ 1 ] ; do
	if [[ $(process_exist ${MONGOS_HOST} ${MONGOS_PORT}) == "1" ]]; then
		break
	fi
	sleep 1
done

bash create_shard_svr.sh -a ${IN} -m ${MONGOS_HOST} -n ${NAME} -p ${PORT} -P ${MONGOS_PORT}
