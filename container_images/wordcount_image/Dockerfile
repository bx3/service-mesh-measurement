FROM rust:1.50
WORKDIR /home/app
COPY ./wordcount .
EXPOSE 40000/tcp
RUN cargo install --path .
RUN apt-get update && apt-get install -y tcpdump 
RUN apt-get update && apt-get install -y tcpflow 
COPY start.sh /home/app
RUN ["chmod", "+x", "/home/app/start.sh"]
ENTRYPOINT /home/app/start.sh
