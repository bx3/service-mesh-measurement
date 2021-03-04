#!/bin/bash
reverse  0.0.0.0:80 &
tcpdump "port 80" -x 
