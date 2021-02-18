#!/bin/bash

# create an image tagged with 'my-app', set root to be current dir
cd reverse_image
docker build -t reverse-app .
cd ../wordcount_image
docker build -t wordcount-app .
cd ../ingress_image
docker build -t ingress-app .


# run image called my-app and name the instance be app, meanwhile expose port 8080
# docker run -p 8080:8080/tcp --rm --name running-app3 my-app
