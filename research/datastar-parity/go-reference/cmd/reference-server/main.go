package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/starfederation/datastar-go/datastar"
)

var (
	address = flag.String("address", "127.0.0.1:8099", "listen address")
	coding  = flag.String("coding", "identity", "identity, idiomatic, or equivalent")
)

func main() {
	flag.Parse()
	http.HandleFunc("/finite", finite)
	http.HandleFunc("/progressive", progressive)
	http.HandleFunc("/persistent", persistent)
	log.Printf("Go Datastar reference listening on http://%s (%s)", *address, *coding)
	log.Fatal(http.ListenAndServe(*address, nil))
}

func stream(w http.ResponseWriter, r *http.Request) *datastar.ServerSentEventGenerator {
	switch *coding {
	case "identity":
		return datastar.NewSSE(w, r)
	case "idiomatic":
		return datastar.NewSSE(w, r, datastar.WithCompression())
	case "equivalent":
		return datastar.NewSSE(w, r, datastar.WithCompression(
			datastar.WithBrotli(datastar.WithBrotliLevel(4), datastar.WithBrotliLGWin(18)),
			datastar.WithForced(),
		))
	default:
		panic("invalid -coding")
	}
}

func finite(w http.ResponseWriter, r *http.Request) {
	_ = stream(w, r).PatchElements(`<div id="result">complete</div>`)
}

func progressive(w http.ResponseWriter, r *http.Request) {
	sse := stream(w, r)
	for stage := 1; stage <= 3; stage++ {
		if err := sse.PatchElements(fmt.Sprintf(`<div id="stage">%d</div>`, stage)); err != nil {
			return
		}
		if stage != 3 {
			time.Sleep(100 * time.Millisecond)
		}
	}
}

func persistent(w http.ResponseWriter, r *http.Request) {
	sse := stream(w, r)
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for revision := 1; ; revision++ {
		select {
		case <-r.Context().Done():
			return
		case <-ticker.C:
			if err := sse.PatchElements(
				`<div id="revision">`+strconv.Itoa(revision)+`</div>`,
				datastar.WithPatchElementsEventID(strconv.Itoa(revision)),
			); err != nil {
				return
			}
		}
	}
}
