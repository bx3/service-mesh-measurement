FROM rust:1.50
WORKDIR /home/app
COPY ./ingress .
EXPOSE 40000/tcp
RUN cargo install --path .
ENTRYPOINT ["ingress", "127.0.0.1:40000", "wordcount-service:40000", "reverse-service:40000"]
