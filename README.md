This project is originally developed as a service mesh measurement.

The container images are stored under image.

git clone https://github.com/brendangregg/FlameGraph.git ./testbed/script/FlameGraph

To see all options, 

cd testbed && ./run.sh help

To take a remote measurement experiment

0  : ./run.sh config-ssh-agent           # Start ssh agent for every terminals to be used for remote control
1  : ./run.sh start-eks aws/cluster.yaml # Generates an EKS cluster based on yaml file. Take 20mins ...
2  : ./run.sh setup-eks-node             # Setup local environment allowing easier access to the eks node
                                         # install packages to the remote EKS nodes
                                         # note, need manual procedure to change port secuirty policy
3.1: ./run.sh run-kube hyper_app         # Run a kubernetes cluster on the EKS node using yaml configs under directory
3.2: ./run.sh run-istio hyper_app        # Run an istio cluster on the EKS node using yaml configs under directory
3.3: kubectl get pods                    # Make sure all pods are running
4.1: ./run.sh add-gen-instance           # Create a seperate EC2 instance responsible for generating http request
                                         # Setup local environment automatically
                                         # Install packages to remote sites
4.2: ./run.sh setup-gen-pkg              # Setup running binary to the EC2 generator, if previous step fails due to EC2 init
4.3: cat gen-instance.txt && ssh <id>    # Log into EC2 generator with id stored inside gen-instance.txt 
5.1: ./run.sh r-gen-data h               # Begin generating HTTP requests with generator details
5.2: ./run.sh r-gen-data h               # Test the pipeline, turn verbose flag on to print the result locally
                                         # 3000 msg of 10 bytes roughly takes 50 sec to finish, given N(10,2) wait time
6  : ./run.sh ssh-perf 99 30 name        # While HTTP requests are sent, Start Perfermance measurement for 30sec with named result
                                         # manual procedure is needed to read data, Give a meaningful name
                                         # for example, kube-8gen-10ms_2ms-10len, kube experiment with 8 gen whose every next request
                                         # wait for a normal distributed time with mean 10ms, std 2ms. Payload size=10
7  : ./run.sh r-clean-proc               # Clean the EC2 generator process, in case the generator command(5) is pre-empted
...
n-2: ./run.sh stop                       # this stop kubernetes or istio services over EKS node
n-1: ./run.sh rm-gen-instance            # this terminate the seperate EC2 generator
n  : ./run.sh stop-eks                   # this terminate all EKS resources, including CloudFormation, worker nodes
