#!/bin/bash

# running order matters. ip is located with environment variable
# run wordcount service
kubectl apply -f wordcount-svc.yaml
kubectl apply -f wordcount-deploy.yaml
# run reverse service
kubectl apply -f reverse-svc.yaml
kubectl apply -f reverse-deploy.yaml
# run ingress service
kubectl apply -f ingress-svc.yaml
kubectl apply -f ingress-deploy.yaml

sleep 2
ip=$(minikube ip)
port=30009  # is hard coded in the ingress-svc.yaml file
curl --header "Content-Type: application/json" --request POST --data '{"text":"test test","mid":"1"}' http://${ip}:${port}/run


