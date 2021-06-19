#!/bin/bash
ingress 0.0.0.0:80 ${WORDCOUNT_SVC_SERVICE_HOST}:${WORDCOUNT_SVC_SERVICE_PORT} ${REVERSE_SVC_SERVICE_HOST}:${REVERSE_SVC_SERVICE_PORT}
#pid="$!"
#top -b -n 2 -d 0.2 -p $pid | tail -1 | awk '{print $9}'
#tcpdump -s 0 -A "port 80" 
