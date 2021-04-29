package main

import(
	"net/http"
    "fmt"
    "io/ioutil"
    "bytes"
    "flag"
    "time"
    "os"
)

func main() {
    var dataCommand = flag.NewFlagSet("data", flag.ExitOnError)
    numTrans := dataCommand.Int("num", 1, "set num transaction")
    dur := dataCommand.Int("interval", 500, "set transmission interval in millisec")


    if len(os.Args) < 2 {
        fmt.Println("Subcommand data")
        os.Exit(1)
    }
    switch os.Args[1] {
        case "data":
            dataCommand.Parse(os.Args[2:])
            send_data(*numTrans, *dur)
        default:
            fmt.Println("Subcommand data")
            os.Exit(1)
    }
}

func send_data(numTrans int, dur int) {
    fmt.Println(numTrans)
    fmt.Println(dur)

    for i := 0; i < numTrans; i++ {
        httpposturl := "http://127.0.0.1:30009/run"
        fmt.Println("HTTP JSON POST URL:", httpposturl)

        var jsonData = []byte(`{
            "text": "test test",
            "mid": "1"
        }`)
        request, error := http.NewRequest("POST", httpposturl, bytes.NewBuffer(jsonData))
        request.Header.Set("Content-Type", "application/json; charset=UTF-8")

        client := &http.Client{}
        response, error := client.Do(request)
        if error != nil {
            panic(error)
        }
        defer response.Body.Close()

        fmt.Println("response Status:", response.Status)
        fmt.Println("response Headers:", response.Header)
        body, _ := ioutil.ReadAll(response.Body)
        fmt.Println("response Body:", string(body))

        time.Sleep(time.Duration(dur) * time.Millisecond)
    }
}
