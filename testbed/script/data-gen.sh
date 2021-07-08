#!/bin/bash
trap kill_procs SIGINT

function kill_procs() {
    echo "STOP"
    for pid in $pids; do
        echo "kill process $pid"
        kill $pid
    done
}

if [ "$#" -ne 8 ]; then
    tput setaf 1
    echo "Usage. sock<str> num_gen<int> interval<int> num_msg<int> var<int> verbose<bool> length<int> goCommand<str>"
    echo "time in milliseconds; sock ip:port"
    echo "Example. ./data-gen.sh 192.168.49.2:30009 4 500 5 50 true 10 text"
    tput sgr0
    exit 1
fi
sock=$1
num_gen=$2
interval=$3
num_msg=$4
variance=$5
verbose=$6
length=$7
goCommand=$8
pids=""

# log includes: start.txt, pids.txt, proc{i}.txt
# gen includes: gen{i}

rm -rf "/home/ubuntu/gen"
rm -rf "/home/ubuntu/log"
mkdir -p "/home/ubuntu/gen"
mkdir -p "/home/ubuntu/log"

echo "Start at $(($(date +%s%N)/1000000)) ms" > "/home/ubuntu/log/start.txt"
for i in $(seq 1 $num_gen); do
    outpath="/home/ubuntu/gen/gen$i"
    nohup ./data-gen/data-gen $goCommand -sock=$sock -interval=${interval} -num=${num_msg} -var=$variance -verbose=$verbose -length=$length -outpath=$outpath &> "/home/ubuntu/log/proc$i.txt" &
    echo $! >> /home/ubuntu/log/pids.txt
    echo "$outpath started at $(($(date +%s%N)/1000000)) ms" >> "/home/ubuntu/log/start.txt"
done
