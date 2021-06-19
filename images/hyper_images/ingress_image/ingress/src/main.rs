#![deny(warnings)]
#![warn(rust_2018_idioms)]
//use std::convert::Infallible;

use hyper::service::{make_service_fn, service_fn};
use hyper::{Body, Request, Response, Server};
use hyper::{Method, Client};
use std::net::SocketAddr;
use std::env;

//, , sock_reverse: String

async fn call_service(in_req: Request<Body>, sock_echo: String, sock_reverse: String) -> Result<Response<Body>, Box<dyn std::error::Error + Send + Sync>> {
    let client = Client::new();
    let data = hyper::body::to_bytes(in_req.into_body()).await?;
    let echo_data = data.clone();
    let echo_fut = async {
        let req = Request::builder()
            .method(Method::POST)
            .uri("http://".to_owned() + &sock_echo + "/echo")
            .body(hyper::body::Body::from(echo_data))
            .expect("request builder");

        let resp = client.request(req).await?;
        hyper::body::to_bytes(resp.into_body()).await
    };

    let reverse_fut = async {
        let req = Request::builder()
            .method(Method::POST)
            .uri("http://".to_owned() + &sock_reverse + "/echo/reversed")
            .body(hyper::body::Body::from(data))
            .expect("request builder");

        let resp = client.request(req).await?;
        hyper::body::to_bytes(resp.into_body()).await
    };

    let (echo, reverse) = futures::try_join!(echo_fut, reverse_fut)?;

    Ok(Response::new(Body::from([echo, reverse].concat())))
}

#[tokio::main]
pub async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        panic!("Error. Input needs to contain: server socket, wordcount socket, reverse socket");
    }
    let server_socket: SocketAddr = args[1]
        .parse()
        .expect("Unable to parse socket address");
    let echo_sock = &args[2];
    let reverse_sock = &args[3];

    //let addr = ([127, 0, 0, 1], 50000).into();
    //let echo_sock: String = "127.0.0.1:50001".to_owned();
    //let reverse_sock: String = "127.0.0.1:50001".to_owned();

    // For every connection, we must make a `Service` to handle all
    // incoming HTTP requests on said connection.
    let make_svc = make_service_fn(|_conn| {
        // This is the `Service` that will handle the connection.
        // `service_fn` is a helper to convert a function that
        // returns a Response into a `Service`.
        //
        let echo_sock_copy: String = echo_sock.clone();
        let reverse_sock_copy: String = reverse_sock.clone();
        async { Ok::<_, hyper::Error>(service_fn(move |_conn| 
                    call_service(_conn, echo_sock_copy.clone(), reverse_sock_copy.clone()))) }} );


    let server = Server::bind(&server_socket).serve(make_svc);

    println!("Listening on http://{}", server_socket);

    server.await?;

    Ok(())
}
