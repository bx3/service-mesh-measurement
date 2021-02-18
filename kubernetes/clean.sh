#!/bin/bash
#kubectl delete service reverse wordcount ingress
#kubectl delete deployment reverse-deployment wordcount-deployment ingress-deployment

kubectl delete service ingress-service wordcount-service
kubectl delete deployment ingress-deployment wordcount-deployment
