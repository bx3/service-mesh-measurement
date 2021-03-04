#!/bin/bash
#kubectl delete service reverse wordcount ingress
#kubectl delete deployment reverse-deployment wordcount-deployment ingress-deployment

kubectl delete service ingress-svc wordcount-svc reverse-svc
kubectl delete deployment ingress-deploy wordcount-deploy reverse-deploy
