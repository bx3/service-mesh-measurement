#!/bin/bash
trap kill_procs SIGINT

GENERATOR_LAUNCH_TEMPLATE=lt-07a4ac67dc12a17b0
s3_prefix="https://service-mesh-app.s3.us-west-2.amazonaws.com"
num_proc_per_gen=2

function kill_procs() {
    echo "STOP"
    for pid in $pids; do 
        echo "kill process $pid"
        kill $pid
    done
}

function gen_data {
    if [ "$#" -ne 8 ]; then
        tput setaf 1 
        echo "Usage. sock<str> num_gen<int> interval<int> num_msg<int> var<int> verbose<bool> length<int>"
        echo "time in milliseconds; sock ip:port"
        echo "Example. ./run.sh gen-data 192.168.49.2:30009 4 500 5 50 true 10"
        tput sgr0
        exit 1
    fi
    local sock=$1
    local num_gen=$2
    local interval=$3
    local num_msg=$4
    local variance=$5
    local verbose=$6
    local length=$7
    local goSubcommand=$8
    local pids=""
    mkdir -p "./output/local"
    for i in $(seq 1 $num_gen); do
        outpath="output/local/gen$i"
        ./data-gen/data-gen $goSubcommand -sock=$sock -interval=${interval} -num=${num_msg} -var=$variance -verbose=$verbose -length=$length -outpath=$outpath &
        #echo "./data-gen/data-gen $goSubcommand -sock=$sock -interval=${interval} -num=${num_msg} -var=$variance -verbose=$verbose -length=$length -outpath='$outpath'"
        pid="$!"
        pids="$pids $pid"
    done
    for pid in $pids; do
        wait $pid
    done
}

function confirm_gen_started {
    nodes=$(cat gen-instance.txt)
    gen_instances=""
    gen_ips=""

    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"

        while [ 1 ]; do
            result=$(ssh $instanceId cat /home/ubuntu/log/start.txt 2>/dev/null | wc -l)
            echo $result
            if [ $result -lt 3 ]; then
                sleep 1
            else
                break
            fi
        done    
    done

}

function check_gen_finished {
    nodes=$(cat gen-instance.txt)
    gen_instances=""
    gen_ips=""

    while [ 1 ]; do
        all_finish=1
        for node in $nodes; do
            local instanceId 
            local ip
            IFS=',' read -r instanceId ip  <<< "$node"
            num_finish=$(ssh $instanceId ls /home/ubuntu/gen 2>/dev/null | wc -l)

            if [ ${num_finish} -ne ${num_proc_per_gen} ]; then
                echo "gen ${instanceId} alreay finishes ${num_finish} instances"
                all_finish=0
            else
                echo "Done. gen ${instanceId}. Increase number of msg"
            fi
        done

        if [ ${all_finish} -eq 1 ]; then
            echo "All generator completed"
            break
        fi
        sleep 1
    done
}

function remote_gen_data {
    if [ "$#" -ne 7 ]; then
        tput setaf 3 
        echo "Create generator processes for each instances in gen_instances.txt"
        echo "Usage.                        num_gen_process<int> interval<int> num_msg<int> var<int> verbose<bool> length<int>"
        echo "Example. ./run.sh r-gen-data        2                 500          5            50       true          10      "
        echo "time in milliseconds; sock ip:port. "
        tput sgr0
        exit 1
    fi

    experiment_name=$(cat experiment.txt)
    nodes=$(cat gen-instance.txt)
    gen_instances=""
    gen_ips=""
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        gen_instances="$gen_instances $instanceId"
        gen_ips="$gen_ips $ip"
        local_gen_out="./output/${experiment_name}/${instanceId}"
        rm -rf ${local_gen_out}
        mkdir -p ${local_gen_out}
    done

    nodes=$(cat eks-instance.txt)
    eks_instances=""
    eks_ip=""
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        eks_instances="$eks_instances $instanceId"
        eks_ip="$eks_ips $ip"
    done

    for gen_instance in ${gen_instances}; do 
        ssh ${gen_instance} "/home/ubuntu/data-gen.sh ${eks_ips}:30009 $@" >/dev/null 2>&1
    done
}

function fetch_gen_data {
    experiment_name=$(cat experiment.txt)
    nodes=$(cat gen-instance.txt)
    echo "Fetch data from EC2 instances"
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        local_gen_out="./output/${experiment_name}/${instanceId}"
        scp -r ${instanceId}:/home/ubuntu/gen ${local_gen_out}/gen &> /dev/null
        scp -r ${instanceId}:/home/ubuntu/log ${local_gen_out}/log &> /dev/null
    done
}

function remote_clean_proc {
    nodes=$(cat gen-instance.txt)
    gen_instances=""
    gen_ips=""
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        gen_instances="$gen_instances $instanceId"
        gen_ips="$gen_ips $ip"
    done
    echo 
    ssh ${gen_instances} -- "pkill -9 data-gen"
}

function quick_gen {
    curl --request POST --data "test123" http://$1/run
}

function quick_json_gen {
    curl --header "Content-Type: application/json" --request POST --data '{"text":"test test","mid":"1"}' http://$1/run
}

function add_gen_instances {
    num_instance=$1
    while true; do
        read -p "Do you wish to run ${num_instance} instances?  " yn
        case $yn in
            [Yy]* ) echo "Start instance generation"; break ;;
            [Nn]* ) exit 0 ;;
            * ) echo "Answer yes or no" ;;
        esac
    done
    add_gen_instances_internal ${num_instance}
}

function add_gen_instances_internal {
    num_instance=$1
    instances=""
    echo "Launch AWS ${num_instance} Generator instance"
    for i in $(seq 1 ${num_instance}); do
        local instance=$(aws ec2 run-instances --launch-template LaunchTemplateId=${GENERATOR_LAUNCH_TEMPLATE} --query 'Instances[*].InstanceId' | jq -r '. | join(" ")')
        instances="$instances $instance"
    done
    tput setaf 2 
    echo "Generator id $instances. Wait for status ok for all"
    tput sgr0

    # aws ec2 wait instance-status-ok --instance-ids $instances TOO SLOW
    # configre local env for instances
    rm -f gen-instance.txt
    while [ 1 ]; do 
        details=$(aws ec2 describe-instances --instance-ids $instances --query "Reservations[*].Instances[*].{pubip:PublicIpAddress,id:InstanceId,privateip:PrivateIpAddress}[]")
        a=$(echo $details | jq -c '.[].pubip') 
        b=$(echo $a | grep null &>/dev/null)
        echo a $a
        echo b $b
        if  echo $details | jq -c '.[].pubip' | grep null &>/dev/null ; then
            echo 'sleep 3'
            sleep 3
            continue
        else
            break
        fi
    done


    rm -f ~/.ssh/config.d/serviceMesh
    setup_eks_ssh
    for instance in $instances; do
        details=$(aws ec2 describe-instances --instance-ids $instance --query "Reservations[*].Instances[*].{pubip:PublicIpAddress,id:InstanceId,privateip:PrivateIpAddress}[]")
        info=$(echo "$details" | jq -c '.[]')
        echo $info > details
        local instanceId=$(echo $info | jq -r '.id')
        local ip=$(echo $info | jq -r '.pubip')
        mkdir -p ~/.ssh/config.d
        echo "$instanceId,$ip" >> gen-instance.txt
        # setup up ssh
        echo "Host $instanceId" >> ~/.ssh/config.d/serviceMesh
        echo "    Hostname $ip" >> ~/.ssh/config.d/serviceMesh
        echo "    User ubuntu" >> ~/.ssh/config.d/serviceMesh
        echo "    IdentityFile ~/.ssh/bowen.pem" >> ~/.ssh/config.d/serviceMesh
        echo "    StrictHostKeyChecking no" >> ~/.ssh/config.d/serviceMesh
        echo "    UserKnownHostsFile=/dev/null" >> ~/.ssh/config.d/serviceMesh
        echo "" >> ~/.ssh/config.d/serviceMesh
    done
    aws ec2 wait instance-running --instance-ids $instances
    echo "All instances started"
}

function setup_gen_pkg {
    nodes=$(cat gen-instance.txt)
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        scp -r ./data-gen $instanceId:/home/ubuntu &> /dev/null
        scp script/data-gen.sh $instanceId:/home/ubuntu &> /dev/null
        ssh $instanceId -- "chmod +x data-gen.sh"
    done
    
    tput setaf 2 
    echo "data-gen transferred"
    tput sgr0
}

function rm_gen_instance {
    nodes=$(cat gen-instance.txt)
    instances=""
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        instances="$instances $instanceId"
    done
    aws ec2 terminate-instances --instance-ids $instances
    tput setaf 2 
    echo "Terminate Instances"
    tput sgr0
}

function start_minikube_trace {
    if [ "$#" -lt 1 ]; then
        tput setaf 1 
        echo "Usage. list of container ids seperated by space"
        echo "Example. ./run.sh start-minikube-trace cid1 cid2 .."
        tput sgr0
        exit 1
    fi
    #in_proxy_cid=d2f5eb99d814
    #wc_proxy_cid=f605d910e7f9
    #re_proxy_cid=20b00878ce79

    #in_app_cid=ec3c9daa5696
    #wc_app_cid=e2a7b3f955bd
    #re_app_cid=55cc1afa4bb1

    rm -f experiment.txt

    start_time=$(date +%s)
    echo "START EXP ${start_time}" # >> experiment.txt


    #cids="${in_proxy_cid} ${in_app_cid} ${wc_proxy_cid} ${wc_app_cid} ${re_proxy_cid} ${re_app_cid} "
    cids=${@:1}
    for cid in $cids; do
        pid=$(docker inspect $cid --format '{{ .State.Pid }}')
        name=$(docker inspect $cid --format '{{ .Name }}')
        iptable_name="iptable-${name:1:25}"
        echo "$pid,${iptable_name}" >> experiment.txt
    done

    echo "Get Network open file Before EXP"
    netBeforeDirname=netFile_store_before
    rm -rf $netBeforeDirname
    mkdir $netBeforeDirname
    for cid in $cids; do
        pid=$(docker inspect $cid --format '{{ .State.Pid }}')
        name=$(docker inspect $cid --format '{{ .Name }}')
        netBefore_name="lsof-${name:1:25}"
        if [[ $name != *"istio"* ]]; then
        # echo $name $pid
            sudo nsenter -t $pid -n lsof -i -n -P > ${netBeforeDirname}/${netBefore_name}
        fi
    done


    ipDirname=iptables_store
    rm -rf $ipDirname
    mkdir $ipDirname
    echo "Get Iptables"
    for cid in $cids; do
        pid=$(docker inspect $cid --format '{{ .State.Pid }}')
        name=$(docker inspect $cid --format '{{ .Name }}')
        iptable_name="rule-${name:1:25}"
        sudo nsenter -t $pid -n iptables -t nat -S > ${ipDirname}/${iptable_name}
    done

    traceDirname=tcpdump_store
    rm -rf $traceDirname
    mkdir $traceDirname

    pidwaits=""
    echo "Start tcpdump trace"
    for cid in $cids; do
        pid=$(docker inspect $cid --format '{{ .State.Pid }}')
        name=$(docker inspect $cid --format '{{ .Name }}')
        trace_name="trace-${name:1:25}"
        sudo nsenter -t $pid -n tcpdump -A -i any -n --time-stamp-precision=nano > ${traceDirname}/${trace_name} &
        pidwait="$!"
        pidwaits="$pidwaits $pidwait"
    done

    echo "wait $pidwaits"
    for pid in $pidwaits; do
        wait $pid
    done
}

function update_meta {
    if [ "$#" -ne 1 ]; then
        tput setaf 1 
        echo "Need a directory including yaml obj. Update service.txt, deploy.txt"
        echo "pip install shyaml"
        tput sgr0
        exit 1
    fi
    > "service.txt"
    > "deploy.txt"
    files=$(ls $1)
    for g in $files; do
        filepath="$1/$g"
        name=$(cat $filepath | shyaml get-value "metadata.name")
        objtype=$(cat $filepath | shyaml get-value "kind")
        if [ "$objtype" = "Service" ]; then
            echo $name >> "service.txt"
        elif [ "$objtype" = "Deployment" ]; then
            echo $name >> "deploy.txt"
        else
            echo "Unknown objtype $objtype"
            exit 1
        fi
    done
}

function run_kube {
    if [ "$#" -ne 1 ]; then
        tput setaf 1 
        echo "Usage. default run all yaml files under directory"
        echo "Example. ./run.sh run-kube app"
        tput sgr0
        exit 1
    fi
    # disable istio 
    kubectl label namespace default istio-injection=disabled --overwrite

    update_meta $1
    dirname=${1%/}
    files=$(ls $dirname/*svc*)   
    for g in $files; do
        echo "kubectl apply -f $g"
        kubectl apply -f $g
    done

    files=$(ls $dirname/*deploy*)   
    for g in $files; do
        echo "kubectl apply -f $g"
        kubectl apply -f $g
    done
}

function run_istio {
    if [ "$#" -ne 1 ]; then
        tput setaf 1 
        echo "Usage. default run all yaml files under directory"
        echo "Example. ./run.sh run-istio app"
        tput sgr0
        exit 1
    fi
    # install and enable automatic istio injection
    istioctl install
    kubectl label namespace default istio-injection=enabled --overwrite
    update_meta $1
    dirname=${1%/}
    files=$(ls $dirname/*svc*)   
    for g in $files; do
        kubectl apply -f $g
    done

    files=$(ls $dirname/*deploy*)   
    for g in $files; do
        kubectl apply -f $g
    done
}

function disable_istio_encrypt {
    kubectl apply -f script/peerAuth.yaml
}

function stop_service {
    services=$(cat service.txt)
    deploys=$(cat deploy.txt)
    kubectl delete service $services
    kubectl delete deployment $deploys
    rm service.txt
    rm deploy.txt
}

function start_eks {
    if [ "$#" -ne 1 ]; then
        tput setaf 1 
        echo "Usage. run eks yaml file to start a eks cluster"
        echo "Example. ./run.sh start_eks aws/cluster.yaml"
        tput sgr0
        exit 1
    fi
    eksctl create cluster -f $1
    # TODO add eksdata to .ssh
    #echo "$id,$ip" >> instances.txt
    #echo "Host $id" >> ~/.ssh/config.d/exp
    #echo "    Hostname $ip" >> ~/.ssh/config.d/exp
    #echo "    User root" >> ~/.ssh/config.d/exp
    #echo "    IdentityFile ~/.ssh/id_rsa" >> ~/.ssh/config.d/exp
    #echo "    StrictHostKeyChecking no" >> ~/.ssh/config.d/exp
    #echo "    UserKnownHostsFile=/dev/null" >> ~/.ssh/config.d/exp
    #echo "" >> ~/.ssh/config.d/exp
}

function stop_eks {
    echo "Run -> eksctl get cluster"
    echo "Then Run -> eksctl delete cluster --name <cluster-name>"
    kubectl get svc --all-namespaces
}

function build_image {
    echo "Run -> docker build -t bx33/<image name>:latest ."
    echo "Inside Dockerfile directory of the image"
    echo "Run -> docker push bx33/<image name>:<tag>"
    echo "For pushing image to docker hub"
}

function start_exp {
    if [ "$#" -ne 9 ]; then
        tput setaf 1 
        echo "Usage. start generators and takes measurements to eks node"
        echo "./run.sh start-exp          freq<int> time<int> name<str> num_gen-instance<int> interval<int> num_msg<int> var<int> verbose<bool> length<int>"
        echo "Example: ./run.sh start-exp  99        30       test-exp               2           10            8000       2          false         10" 
        echo "output is stored under name directory, including profile and gen info"
        tput sgr0
        exit 1
    fi

    freq=$1
    period=$2
    name=$3
    num_instance=$4
    pids=""
    gpids="" 

    mkdir -p "output/$name"
    echo "$name" > experiment.txt
    echo "./run.sh start-exp ${@}" > "output/$name/summary.txt"
    echo "time_start: $(($(date +%s%N)/1000000))" >> "output/$name/summary.txt"

    prepare_perf $freq $period 

    add_gen_instances_internal ${num_instance}

    echo "num_instance: ${num_instance}" >> "output/$name/summary.txt"

    sync_payload
    echo "time_synced_payload: $(($(date +%s%N)/1000000))" >> "output/$name/summary.txt"
    echo "All generator synced payload"

    # start remote gen
    remote_gen_data ${num_proc_per_gen} ${@:5} "text"
    confirm_gen_started
    
    echo "time_confirmed_all_genx: $(($(date +%s%N)/1000000))" >> "output/$name/summary.txt"
    echo "lag_time: 3" >> "output/$name/summary.txt"

    echo "Confirmed all generators started. Start perf profile 3 sec later..." 
    sleep 3

    echo "Start Perf "
    echo "time_start_perf: $(($(date +%s%N)/1000000))" >> "output/$name/summary.txt"

    start_perf
    echo "wait_perf_time: $(($period-1))" >> "output/$name/summary.txt"

    echo "Sleep $(($period-1)) sec then check if perf finishes" 
    sleep $(($period-1))
    check_perf_finish
    echo "time_complete_perf: $(($(date +%s%N)/1000000))" >> "output/$name/summary.txt"

    echo "Wait All generators stop"
    check_gen_finished
    echo "time_complete_gens: $(($(date +%s%N)/1000000))" >> "output/$name/summary.txt"


    echo "Fetch generator data."
    fetch_gen_data 
    echo "Finish gen-data Fetch. Fetch and run perf data "
    fetch_handle_perf_data
}

function start_exp_group {
    if [ "$#" -ne 8 ]; then
        tput setaf 1 
        echo "Usage. start generators and takes measurements to eks node"
        echo "./run.sh start-exp             app-dir<str>    freq<int> period<int> gen-interval<int> num_msg<int> var<int> verbose<bool> length<int>"
        echo "Example: ./run.sh start-exp    hyper_app       99        30               10            8000       2          false         10" 
        echo "output is stored under name directory, including profile and gen info"
        tput sgr0
        exit 1
    fi

    app_dir=$1
    freq=$2
    period=$3
    interval=$4
    num_msg=$5
    variance=$6
    verbose=$7
    length=$8

    num_gens="4 8 16 32"
    # run kubernetes
    #run-kube ${app_dir}
    for num_gen in ${num_gens}; do
        #name="kube-${num_gen}gen-${interval}ms-${length}len-${num_msg}msg"
        #echo "Start exp $name"
        #start_exp ${freq} ${period} ${name} ${num_gen} ${interval} ${num_msg} ${variance} ${verbose} ${length}
        #echo "Finish exp $name"
        #stop_service
        #sleep 10
        ## run istio
        #run-istio ${app_dir} 

        # wait for container to start
        #sleep 30 

        echo "Start exp $name"
        name="istio-${num_gen}gen-${interval}ms-${length}len-${num_msg}msg"
        start_exp ${freq} ${period} ${name} ${num_gen} ${interval} ${num_msg} ${variance} ${verbose} ${length}
        echo "Finish exp $name"
        
        rm_gen_instance

        sleep 10
    done

    echo "Start Analyze and plot "
    # analyze the data 
    ./script/read_measure.py output 'tokio-runtime-w' y
    echo 'Run ->'
    echo "scp turing:/home/bowen/system-network/service-mesh-measurement/testbed/output/perf-analysis.png ."
    stop_service
}


function fetch_handle_perf_data {
    nodes=$(cat eks-instance.txt)
    name=$(cat experiment.txt)

    instances=""
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        instances="$instanceId"
    done   

    echo "sudo perf script --header -i perf.data > out.stacks" | ssh $instances &> /dev/null
    mkdir -p ./output/${name}
    echo "scp $instances:/home/ec2-user/out.stacks ./output/${name}/out.stacks"

    scp $instances:/home/ec2-user/out.stacks ./output/${name}/out.stacks &> /dev/null
    ./script/FlameGraph/stackcollapse-perf.pl < ./output/${name}/out.stacks | ./script/FlameGraph/flamegraph.pl --hash > output/${name}/out.svg
    scp $instances:/home/ec2-user/time.txt ./output/${name}/time.txt &>/dev/null

    echo "Run -> "
    echo "scp turing:/home/bowen/system-network/service-mesh-measurement/testbed/output/${name}/out.svg ."
    echo "To fetch the plot"
}

function start_perf {
    nodes=$(cat eks-instance.txt)
    instances=""
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        instances="$instanceId"
    done
    ssh $instances "nohup bash /home/ec2-user/start_perf.sh > /dev/null 2>&1" &
}

function check_perf_finish {
    nodes=$(cat eks-instance.txt)
    eks_instances=""
    eks_ips=""
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        eks_instances="$eks_instances $instanceId"
    done
    
    while [ 1 ]; do
        all_finish=1
        finished=$(ssh $instanceId -- cat /home/ec2-user/time.txt 2>/dev/null)
        if [ $(echo $finished | wc -w) -eq 2 ]; then
            break
        fi
        sleep 1
    done
    used_time=$(awk 'NR > 1 { print $0 - prev } { prev = $0 }' <<< $finished)
    echo "perf finish in ${used_time} milisec"
}

function prepare_perf {
    if [ "$#" -ne 2 ]; then
        tput setaf 1 
        echo "Usage. run perf on eks for some time with sample freq"
        echo "Example. ./run.sh prepare_perf freq time"
        tput sgr0
        exit 1
    fi
    freq=$1
    period=$2
    nodes=$(cat eks-instance.txt)
    instances=""
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        instances="$instanceId"
    done
    echo '#!/bin/bash' > payload/start_perf.sh
    # time is ms
    echo 'echo $(($(date +%s%N)/1000000)) > /home/ec2-user/time.txt ' >> payload/start_perf.sh
    echo "sudo perf record -F $1 -a -g -o /home/ec2-user/perf.data -- sleep $period " >> payload/start_perf.sh
    echo 'echo $(($(date +%s%N)/1000000)) >> /home/ec2-user/time.txt ' >> payload/start_perf.sh
    chmod +x payload/start_perf.sh

    ssh $instances -- "rm -f /home/ec2-user/perf.data && rm -f /home/ec2-user/*.svg && rm -f /home/ec2-user/time.txt && rm -f /home/ec2-user/start_perf.sh" 2> /dev/null
    scp payload/start_perf.sh $instances:/home/ec2-user 2>/dev/null
}

function mini_perf_record {
    if [ "$#" -ne 2 ]; then
        tput setaf 1 
        echo "Usage. run perf on minikube on some time with sample freq"
        echo "Example. ./run.sh mini-perf-record freq-50 time-30"
        tput sgr0
        exit 1
    fi
    freq=$1
    period=$2
    #minikube ssh "rm -f perf.data"
    minikube ssh "sudo perf record -F $1 -a -g -- sleep $2 ; sudo perf script --header > out.stacks"
    echo "Finish perf record and script"
}

function mini_plot {
    mkdir -p output
    scp -i ~/.minikube/machines/minikube/id_rsa docker@$(minikube ip):/home/docker/out.stacks ./output/out.stacks
    ./script/FlameGraph/stackcollapse-perf.pl < output/out.stacks | ./script/FlameGraph/flamegraph.pl --hash > output/out.svg
    echo "Run -> scp turing:/home/bowen/system-network/service-mesh-measurement/testbed/output/out.svg ."
    echo "To fetch the plot"
}

function setup_eks_ssh {
    instanceId=$(kubectl get nodes -o json | jq -r '.items[]' | jq -r '.metadata' | jq -r '.labels' | jq -r '.["alpha.eksctl.io/instance-id"]')
    ip=$(kubectl get nodes -o json | jq -r '.items[]' | jq -r '.status' | jq -r '.addresses' | jq -r '.[] | select(.["type"] == "ExternalIP") | .address')
    echo "Host $instanceId" >> ~/.ssh/config.d/serviceMesh
    echo "    Hostname $ip" >> ~/.ssh/config.d/serviceMesh
    echo "    User ec2-user" >> ~/.ssh/config.d/serviceMesh
    echo "    IdentityFile ~/.ssh/id_rsa" >> ~/.ssh/config.d/serviceMesh
    echo "    StrictHostKeyChecking no" >> ~/.ssh/config.d/serviceMesh
    echo "    UserKnownHostsFile=/dev/null" >> ~/.ssh/config.d/serviceMesh
    echo "" >> ~/.ssh/config.d/serviceMesh
}

# on a single node
function setup_eks_node {
    instanceId=$(kubectl get nodes -o json | jq -r '.items[]' | jq -r '.metadata' | jq -r '.labels' | jq -r '.["alpha.eksctl.io/instance-id"]')
    ip=$(kubectl get nodes -o json | jq -r '.items[]' | jq -r '.status' | jq -r '.addresses' | jq -r '.[] | select(.["type"] == "ExternalIP") | .address')
    echo "$instanceId,$ip" > eks-instance.txt
    echo "Host $instanceId" >> ~/.ssh/config.d/serviceMesh
    echo "    Hostname $ip" >> ~/.ssh/config.d/serviceMesh
    echo "    User ec2-user" >> ~/.ssh/config.d/serviceMesh
    echo "    IdentityFile ~/.ssh/id_rsa" >> ~/.ssh/config.d/serviceMesh
    echo "    StrictHostKeyChecking no" >> ~/.ssh/config.d/serviceMesh
    echo "    UserKnownHostsFile=/dev/null" >> ~/.ssh/config.d/serviceMesh
    echo "" >> ~/.ssh/config.d/serviceMesh
    tput setaf 2 
    echo "Setup EKS node $instanceId"
    tput sgr0

    ssh $instanceId -- "sudo amazon-linux-extras enable BCC -y"
    ssh $instanceId -- "sudo yum install kernel-devel-$(uname -r) -y"
    ssh $instanceId -- "sudo yum install bcc -y"
    ssh $instanceId -- "sudo yum install perf -y"

    # TODO
    echo "Login AWS EC2 and modify inbound rules to Allow data to come in. At 30009"
}

function config_ssh_agent {
    echo "RUN following"
    echo "eval \`ssh-agent -s\`"
    echo "ssh-add ~/.ssh/id_rsa"
}

function upload_payload {
    #pushd data-gen
    #cd data-gen
    #go build -ldflags "-s -w"
    #popd
    tar cvzf payload/data-gen.tar.gz -C ./data-gen . 

    aws s3 cp script/data-gen.sh s3://service-mesh-app
    aws s3 cp payload/data-gen.tar.gz s3://service-mesh-app 

    tar cvzf payload/$id.tar.gz -C payload/$id .
}

function sync_payload {
    nodes=$(cat gen-instance.txt)
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        ssh ${instanceId} -- "rm -rf /home/ubuntu/data-gen* && wget ${s3_prefix}/data-gen.tar.gz -O /home/ubuntu/data-gen.tar.gz && wget ${s3_prefix}/data-gen.sh -O /home/ubuntu/data-gen.sh && mkdir -p /home/ubuntu/data-gen && tar xf /home/ubuntu/data-gen.tar.gz -C /home/ubuntu/data-gen && chmod +x /home/ubuntu/data-gen.sh" >/dev/null
    done   
}

case "$1" in
  help)
    cat <<-EOF
    Manage AWS EKS Nodes
    
      start-eks p              Start EKS cluster
      stop-eks p               Delete EKS cluster
      setup-eks-node           Setup EKS node

    Manage Local Minikube Nodes

      start-minikube-trace l   Start Minikube trace for all containers

    Modify service

      run-kube d               Start kubernetes
      disable-istio-encrypt    Disable istio encryption
      run-istio d              Start istio
      stop                     Stop Services

    Measure service mesh

      start-exp h              Start a measure experiment 
      start-exp-group h        Start a group of experiments (istio, kube, bare)
      ssh-perf fq t            Record CPU activity on AWS nodew
      mini-perf-record fq t    Record CPU activity on minikube
      mini-plot                Get flame graph for minikube perf

    Generate payload

      gen-json-data s n i      Generate json payload to ingress
      gen-data s n i           Generate text string payload to ingress
      q-gen ip:port            Generate a msg
      q-json-gen ip:port       Generate a json msg
      r-gen-data               Generate payload from AWS instances. Return immediately
      fetch-gen-data           Fetch data from AWS
      r-clean-proc             Clean payload generating process on AWS

      add-gen-instances n      Create AWS instance for sending request
      upload-payload           Upload generator binary to S3
      sync-payload             Request all generators to sync payload from S3   
      setup-gen-pkg            Setup AWS generator necessary binary
      rm-gen-instance          Remove AWS generator instance

    Build images

      build-image              Build container images

    Utils

      config-ssh-agent         Start ssh agent
      get-proxy-config         Run "istioctl profile dump"

EOF
    ;;
  start-eks)
    start_eks $2 ;;
  stop-eks)
    stop_eks ;;
  gen-data)
    gen_data $2 $3 $4 $5 $6 $7 $8 "text" ;;
  gen-json-data)
    gen_data $2 $3 $4 $5 $6 $7 $8 "json" ;;
  q-gen)
    quick_gen $2 ;;
  q-json-gen)
    quick-json-gen $2 ;;
  r-gen-data)
    remote_gen_data $2 $3 $4 $5 $6 $7 $8 "text" ;;
  confirm-gen-started)
    confirm_gen_started ;;
  fetch-gen-data)
    fetch_gen_data ;;
  r-clean-proc)
    remote_clean_proc ;;
  add-gen-instances)
    add_gen_instances $2 ;;
  upload-payload)
    upload_payload ;;
  sync-payload)
    sync_payload ;;
  setup-gen-pkg)
    setup_gen_pkg ;;
  rm-gen-instance)
    rm_gen_instance ;;
  start-minikube-trace)
    start_minikube_trace ${@:2} ;;
  run-kube)
    run_kube $2 ;;
  run-istio)
    run_istio $2 ;;
  disable-istio-encrypt)
    disable_istio_encrypt ;;
  stop)
    stop_service ;;
  build-image)
    build_image ;;
  start-exp)
    start_exp ${@:2} ;;
  start-exp-group)
    start_exp_group ${@:2} ;;
  ssh-perf)
    ssh_perf $2 $3 $4 ;;
  check-perf-finish)
    check_perf_finish ;;
  mini-perf-record)
    mini_perf_record $2 $3 ;;
  mini-plot)
    mini_plot ;;
  setup-eks-node)
    setup_eks_node ;;
  config-ssh-agent)
    config_ssh_agent ;;
*)
  tput setaf 1
  echo "Unknown subcommand" $1
  echo "./run.sh help"
  tput sgr0 ;;
esac
