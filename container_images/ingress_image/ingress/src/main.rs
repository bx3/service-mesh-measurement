extern crate tiny_http;
extern crate rustc_serialize;
use rustc_serialize::json::Json;
use tiny_http::{Server, Response};
use std::collections::HashMap;
use reqwest::Error;
use std::env;

fn rem_first_and_last(value: &str) -> &str {
    let mut chars = value.chars();
    chars.next();
    chars.next_back();
    chars.as_str()
}

fn query_service(data: &HashMap<&str, String>, socket: &str, method: &str) -> std::result::Result<String, reqwest::Error> {
    let wordcount_client = reqwest::blocking::Client::new();
    let url: String = "http://".to_owned() + socket + "/" + method;
    let wordcount_response = match wordcount_client.post(&url)
        .json(data)
        .send() {
        Ok(response) => response,
        Err(e) => 
        {
            return Err(e);
        }
    };
    let wordcount_result = match wordcount_response.text() {
        Ok(re) => re.to_string(),
        Err(e) => {
            return Err(e);
        }
    };
    Ok(wordcount_result)
}


fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        panic!("Error. Input needs to contain: server socket, wordcount socket, reverse socket");
    }
    let server_socket = &args[1];
    let wordcount_socket = &args[2];
    let reverse_socket = &args[3];

    let server = Server::http(server_socket).unwrap();

    for mut request in server.incoming_requests() {
        //let _ = thread::spawn(move || {
        

        match request.url() {
            "/run" => {
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
                let mut map = HashMap::new();
                map.insert("text", text.to_string());
                map.insert("mid", mid.to_string());
                // wordcount. Blocking, can be made threaded, but suppose they forms a chain
                let wordcount_result = match query_service(&map, wordcount_socket, "wordcount") {
                    Ok(result) => result,
                    Err(e) => {
                        println!("Error. wordcount http {}", e);
                        "wordcount error".to_string()
                    }
                };
                let reverse_result = match query_service(&map, reverse_socket, "reverse") {
                    Ok(r) => r,
                    Err(e) => {
                        println!("Error. reverse http {}", e);
                        "reverse error".to_string()
                    }
                };
                let response = Response::from_string(wordcount_result + "\n" + &reverse_result + "\n");
                request.respond(response).expect("Method wordcount. Could not respond");
            },
            "/stop" => {
                println!("server stopped");
                let wordcount_result = query_service(&HashMap::new(), wordcount_socket, "stop").unwrap();
                let reverse_result = query_service(&HashMap::new(), reverse_socket, "stop").unwrap();
                let response = Response::from_string(wordcount_result + "\n" + &reverse_result + "\n" + "gateway server stopped\n");
                request.respond(response).expect("Method stop. Could not respond"); 
                return;
            }
            _ =>{
                let response_msg = format!("Unknown method. {}\n", request.url());
                println!("{}", response_msg);
                let response = Response::from_string(response_msg);
                request.respond(response).expect("Method unknown. Could not respond");
            }
        }
        //});
    }
}
