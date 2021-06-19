extern crate tiny_http;
extern crate rustc_serialize;
use rustc_serialize::json::Json;
use tiny_http::{Server, Response};
use std::env;
use std::thread;

fn rem_first_and_last(value: &str) -> &str {
    let mut chars = value.chars();
    chars.next();
    chars.next_back();
    chars.as_str()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        panic!("Error. Input needs to contain: wordcount socket");
    }
    let socket = &args[1];

    let server = Server::http(socket).unwrap();

    for mut request in server.incoming_requests() {
        let _ = thread::spawn(move || {
            match request.url() {
                "/wordcount" => {
                    let mut content = String::new();
                    request.as_reader().read_to_string(&mut content).unwrap();
                    let json: Json = content.parse().unwrap();
                    let obj = json.as_object().unwrap();
                    let text: String = obj.get("text").unwrap().to_string();
                    let text: String = rem_first_and_last(&text).to_string();
                    let mid_string: String = obj.get("mid").unwrap().to_string();
                    let mid_strip = mid_string.replace("\"", "");
                    let mid = match mid_strip.parse::<u64>()
                    {
                        Ok(i) => i,
                        Err(e) => {
                            panic!("http message id {:?}", e);
                        }
                    };
                    let response = Response::from_string(mid.to_string() + ": " + &(text.len()).to_string());
                    request.respond(response).expect("Method wordcount. Could not respond");
                },
                "/stop" => {
                    println!("server stopped");
                    let response = Response::from_string("Wordcount server stopped\n");
                    request.respond(response).expect("Method stop. Could not respond"); 
                    return;
                }
                _ =>{
                    let response_msg = format!("Unknown method. {}\n",request.url());
                    println!("{}", response_msg);
                    let response = Response::from_string(response_msg);
                    request.respond(response).expect("Method unknown. Could not respond");
                }
            }
        });
    }
}

