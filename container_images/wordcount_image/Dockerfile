FROM rust:1.50
WORKDIR /home/app
COPY ./wordcount .
EXPOSE 40000/tcp
RUN cargo install --path .
ENTRYPOINT ["wordcount", "127.0.0.1:40000"]
