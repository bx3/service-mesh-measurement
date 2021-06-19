FROM rust:1.50
WORKDIR /home/app
COPY ./ingress .
EXPOSE 80/tcp
RUN cargo install --path .
#RUN apt-get update && apt-get install -y tcpdump && apt-get install -y iptables && apt-get install -y vim
#RUN apt-get install -y lsof && apt-get install -y net-tools
COPY start.sh /home/app
RUN ["chmod", "+x", "/home/app/start.sh"]
ENTRYPOINT /home/app/start.sh
