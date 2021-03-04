#!/bin/bash
wordcount 0.0.0.0:80 &
tcpdump "port 80" -x 
