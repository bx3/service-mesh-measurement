#!/bin/bash
wordcount 0.0.0.0:80 &
tcpdump -s 0 -A "port 80"
