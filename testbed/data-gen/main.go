package main

import(
    "net/http"
    "fmt"
    "io/ioutil"
    "bytes"
    "flag"
    "time"
    "os"
    "encoding/json"
    "strconv"
    "math/rand"
)

func main() {
    var dataCommand = flag.NewFlagSet("text", flag.ExitOnError)
    sock := dataCommand.String("sock", "192.168.49.2:30009", "dst sock")
    numTrans := dataCommand.Int("num", 1, "set num transaction")
    dur := dataCommand.Int("interval", 500, "set transmission interval in millisec")
    variance := dataCommand.Int("var", 100, "set transmission interval variance in millisec")
    length := dataCommand.Int("length", 100, "set msg length")
    verbose := dataCommand.Bool("verbose", false, "Print http response")
    outpath := dataCommand.String("outpath", "gen0", "Generator output path name")

    rand.Seed(time.Now().UTC().UnixNano())

    if len(os.Args) < 2 {
        fmt.Println("Subcommand data")
        os.Exit(1)
    }
    switch os.Args[1] {
        case "json":
            dataCommand.Parse(os.Args[2:])
            send_json_data(*sock, *numTrans, *dur, *variance, *verbose, *length, *outpath)
        case "text":
            dataCommand.Parse(os.Args[2:])
            send_text_data(*sock, *numTrans, *dur, *variance, *verbose, *length, *outpath)
        default:
            fmt.Println("Subcommand text json")
            os.Exit(1)
    }
}

type Message struct {
    Text string `json:"text"`
    Mid string `json:"mid"`
}

const letterBytes = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

func check(e error) {
    if e != nil {
        panic(e)
    }
}

func RandStringBytes(n int) string {
    b := make([]byte, n)
    for i := range b {
        b[i] = letterBytes[rand.Intn(len(letterBytes))]
    }
    return string(b)
}

func send_text_data(sock string, numTrans int, interval int, variance int, verbose bool, length int, outpath string) {
    total_service_time := time.Duration(0)
    for i := 0; i < numTrans; i++ {
        httpposturl := "http://" + sock + "/run"
        data := RandStringBytes(length)
        request, error := http.NewRequest("POST", httpposturl, bytes.NewBuffer([]byte(data)))

        client := &http.Client{}

        // Timer start
        start := time.Now()
        response, error := client.Do(request)
        if error != nil {
            panic(error)
        }
        defer response.Body.Close()

        if verbose {
            body, _ := ioutil.ReadAll(response.Body)
            // timer close
            total_service_time += time.Since(start)
            fmt.Println("response Body:", string(body))
        } else {
            ioutil.ReadAll(response.Body)
            // timer close
            total_service_time += time.Since(start)
        }

        dur := int(rand.NormFloat64() * float64(variance)) + interval
        if dur < 0 {
            dur = 0
        }

        time.Sleep(time.Duration(dur) * time.Millisecond)
    }
    f, err := os.Create(outpath)
    check(err)
    output := fmt.Sprintf("%s Finish %d in %d ns", outpath, numTrans, total_service_time.Nanoseconds())
    f.WriteString(output)
    fmt.Println(output)
}

func send_json_data(sock string, numTrans int, interval int, variance int, verbose bool, length int, outpath string) {
    fmt.Println(sock)
    fmt.Println(numTrans)
    fmt.Println(interval)
    fmt.Println(variance)
    for i := 0; i < numTrans; i++ {
        httpposturl := "http://" + sock + "/run"
        //fmt.Println("HTTP JSON POST URL:", httpposturl)
        m := Message{"test test", strconv.Itoa(i)}
        jsonData, _ := json.Marshal(m)

        //fmt.Println("HTTP JSON POST URL:", jsonData)

        //var jsonData = []byte(`{
            //"text": "test test",
            //"mid": "1"
        //}`)
        //fmt.Println("v:", v)
        request, error := http.NewRequest("POST", httpposturl, bytes.NewBuffer(jsonData))
        request.Header.Set("Content-Type", "application/json; charset=UTF-8")

        client := &http.Client{}
        response, error := client.Do(request)
        if error != nil {
            panic(error)
        }
        defer response.Body.Close()

        //fmt.Println("response Status:", response.Status)
        //fmt.Println("response Headers:", response.Header)
        if verbose {
            body, _ := ioutil.ReadAll(response.Body)
            fmt.Println("response Body:", string(body))
        } else {
            ioutil.ReadAll(response.Body)
        }

        dur := int(rand.NormFloat64() * float64(variance)) + interval
        if dur < 0 {
            dur = 0
        }

        time.Sleep(time.Duration(dur) * time.Millisecond)
    }
    fmt.Println("Finish", outpath)
}
