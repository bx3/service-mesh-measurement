FROM rust:1.50
WORKDIR /home/app
COPY ./reverse .
EXPOSE 40000/tcp
RUN cargo install --path .
CMD ["reverse 127.0.0.1:40000"]
