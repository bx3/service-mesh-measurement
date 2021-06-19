#!/bin/bash
trap kill_procs SIGINT

GENERATOR_LAUNCH_TEMPLATE=lt-07a4ac67dc12a17b0

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
    for i in $(seq 1 $num_gen); do
        ./data-gen/data-gen $goSubcommand -sock=$sock -interval=${interval} -num=${num_msg} -var=$variance -verbose=$verbose -length=$length &
        #echo "./data-gen/data-gen $goSubcommand -sock=$sock -interval=${interval} -num=${num_msg} -var=$variance -verbose=$verbose -length=$length "
        pid="$!"
        pids="$pids $pid"
    done
    for pid in $pids; do
        wait $pid
    done
}

function remote_gen_data {
    if [ "$#" -ne 7 ]; then
        tput setaf 3 
        echo "Usage.                        num_gen<int> interval<int> num_msg<int> var<int> verbose<bool> length<int>"
        echo "Example. ./run.sh r-gen-data        4          500          5            50       true          10"
        echo "time in milliseconds; sock ip:port"
        tput sgr0
        exit 1
    fi
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

    nodes=$(cat eks-instance.txt)
    eks_instances=""
    eks_ips=""
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        eks_instances="$eks_instances $instanceId"
        eks_ips="$eks_ips $ip"
    done
    ssh ${gen_instances} -- "/home/ubuntu/data-gen.sh ${eks_ips}:30009 $@"
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

function add_gen_instance {
    echo "Launch AWS Generator instance"
    local instance=$(aws ec2 run-instances --launch-template LaunchTemplateId=${GENERATOR_LAUNCH_TEMPLATE} --query 'Instances[*].InstanceId' | jq -r '. | join(" ")')
    echo "Generator id $instance"
    details=$(aws ec2 describe-instances --instance-ids $instance --query "Reservations[*].Instances[*].{pubip:PublicIpAddress,id:InstanceId,privateip:PrivateIpAddress}[]")
    sleep 8 # make sure instances is allocated
    info=$(echo "$details" | jq -c '.[]')
    echo $info > details

    local instanceId=$(echo $info | jq -r '.id')
    local ip=$(echo $info | jq -r '.pubip')
    mkdir -p ~/.ssh/config.d
    echo "$instanceId,$ip" > gen-instance.txt
    # setup up ssh
    echo "Host $instanceId" >> ~/.ssh/config.d/serviceMesh
    echo "    Hostname $ip" >> ~/.ssh/config.d/serviceMesh
    echo "    User ubuntu" >> ~/.ssh/config.d/serviceMesh
    echo "    IdentityFile ~/.ssh/bowen.pem" >> ~/.ssh/config.d/serviceMesh
    echo "    StrictHostKeyChecking no" >> ~/.ssh/config.d/serviceMesh
    echo "    UserKnownHostsFile=/dev/null" >> ~/.ssh/config.d/serviceMesh
    echo "" >> ~/.ssh/config.d/serviceMesh
    tput setaf 2 
    echo "Generator started"
    tput sgr0

    scp -r ./data-gen $instanceId:/home/ubuntu
    scp script/data-gen.sh $instanceId:/home/ubuntu
    ssh $instanceId -- "chmod +x data-gen.sh"
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
    echo "Run -> kubectl delete svc <service-name> from below"
    echo "Then Run -> eksctl delete cluster --name <cluster-name>"
    kubectl get svc --all-namespaces
}

function build_image {
    echo "Run -> docker build -t bx33/<image name>:latest ."
    echo "Inside Dockerfile directory of the image"
    echo "Run -> docker push bx33/<image name>:<tag>"
    echo "For pushing image to docker hub"
}

function ssh_perf {
    if [ "$#" -ne 3 ]; then
        tput setaf 1 
        echo "Usage. run perf on minikube on some time with sample freq"
        echo "Example. ./run.sh ssh-perf freq time name"
        tput sgr0
        exit 1
    fi
    freq=$1
    period=$2
    name=$3

    nodes=$(cat eks-instance.txt)
    instances=""
    for node in $nodes; do
        local instanceId 
        local ip
        IFS=',' read -r instanceId ip  <<< "$node"
        instances="$instances $instanceId"
    done
    
    ssh $instances -- "rm -f perf.data"
    ssh $instances -- "rm -f *.svg"

    command_str="sudo perf record -F $1 -a -g -o /home/ec2-user/perf.data -- sleep $2 "
    echo ${command_str} | ssh $instances &> /dev/null
    echo "sudo perf script --header -i perf.data > out.stacks" | ssh $instances &> /dev/null
    scp $instances:/home/ec2-user/out.stacks ./output/${name}.stacks
    ./script/FlameGraph/stackcollapse-perf.pl < ./output/${name}.stacks | ./script/FlameGraph/flamegraph.pl --hash > output/${name}.svg

    echo "Run -> "
    echo "scp turing:/home/bowen/system-network/service-mesh-measurement/testbed/output/${name}.svg ."
    echo "To fetch the plot"
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
    eval `ssh-agent -s`
    ssh-add ~/.ssh/id_rsa
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

      ssh-perf fq t            Record CPU activity on AWS nodew
      mini-perf-record fq t    Record CPU activity on minikube
      mini-plot                Get flame graph for minikube perf

    Generate payload

      gen-json-data s n i      Generate json payload to ingress
      gen-data s n i           Generate text string payload to ingress
      q-gen ip:port            Generate a msg
      q-json-gen ip:port       Generate a json msg
      r-gen-data               Generate payload from AWS instances
      r-clean-proc             Clean payload generating process on AWS

      add-gen-instance         Create AWS instance for sending request
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
  r-clean-proc)
    remote_clean_proc ;;
  add-gen-instance)
    add_gen_instance ;;
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
  ssh-perf)
    ssh_perf $2 $3 $4 ;;
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
