#!/bin/bash
trap kill_test SIGINT

pids=""
function kill_test() {
	echo "STOP"
	for pid in $pids; do
		echo "Kill $pid"
		kill $pid
	done
}


if [ "$#" -lt 1 ]; then
	echo "Usgae ./local_run.sh num_msg<int>"
	exit 0
fi

num_msg=$1

ip=127.0.0.1
ingress_port=40000
wordcount_port=40001
reverse_port=40002

cd wordcount_image/wordcount
cargo run $ip:${wordcount_port}&
pid="$!"
pids="$pids $pid"
echo "run wordcount $pid"
sleep 0.1

cd ../../reverse_image/reverse
cargo run $ip:${reverse_port}&
pid="$!"
pids="$pids $pid"
echo "run reverse $pid"
sleep 0.1

cd ../../ingress_image/ingress
cargo run $ip:${ingress_port} $ip:${wordcount_port} $ip:${reverse_port}&
pid="$!"
pids="$pids $pid"
echo "run ingress $pid"

sleep 1

i=0
for (( i=0; i<${num_msg}; i++ )); do
	curl --header "Content-Type: application/json" --request POST --data '{"text":"test test","mid":"'$i'"}' http://$ip:$ingress_port/run
	sleep 0.5
done

kill_test

