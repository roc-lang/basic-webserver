package main

import (
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/starfederation/datastar-go/datastar"
)

var (
	address            = flag.String("address", "127.0.0.1:8099", "listen address")
	coding             = flag.String("coding", "identity", "identity, scale, idiomatic, or equivalent")
	measureAllocations = flag.Bool("measure-allocations", false, "log Go runtime allocation deltas per response")
)

func main() {
	flag.Parse()
	http.HandleFunc("/finite", finite)
	http.HandleFunc("/progressive", progressive)
	http.HandleFunc("/persistent", persistent)
	for _, route := range []string{"/hot-100", "/hot-1000", "/hot-10000", "/hot-4096", "/hot-65536", "/idle"} {
		http.HandleFunc(route, fixedWorkload)
	}
	log.Printf("Go Datastar reference listening on http://%s (%s)", *address, *coding)
	log.Fatal(http.ListenAndServe(*address, nil))
}

func stream(w http.ResponseWriter, r *http.Request) *datastar.ServerSentEventGenerator {
	switch *coding {
	case "identity":
		return datastar.NewSSE(w, r)
	case "idiomatic":
		return datastar.NewSSE(w, r, datastar.WithCompression())
	case "scale":
		return datastar.NewSSE(w, r, datastar.WithCompression(
			datastar.WithBrotli(datastar.WithBrotliLevel(1), datastar.WithBrotliLGWin(11)),
			datastar.WithForced(),
		))
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
	_ = stream(w, r).PatchElements(htmlPayload(256, 1))
}

func progressive(w http.ResponseWriter, r *http.Request) {
	sse := stream(w, r)
	for stage := 1; stage <= 3; stage++ {
		if err := sse.PatchElements(htmlPayload(256, stage)); err != nil {
			return
		}
		if stage != 3 {
			time.Sleep(100 * time.Millisecond)
		}
	}
}

func fixedWorkload(w http.ResponseWriter, r *http.Request) {
	events, payloadBytes, delay := workload(r.URL.Path)
	var before runtime.MemStats
	if *measureAllocations {
		runtime.GC()
		runtime.ReadMemStats(&before)
	}

	sse := stream(w, r)
	for sequence := 1; sequence <= events; sequence++ {
		if err := sse.PatchElements(htmlPayload(payloadBytes, sequence)); err != nil {
			return
		}
		if delay != 0 && sequence != events {
			timer := time.NewTimer(delay)
			select {
			case <-timer.C:
			case <-r.Context().Done():
				timer.Stop()
				return
			}
		}
	}

	if *measureAllocations {
		var after runtime.MemStats
		runtime.ReadMemStats(&after)
		result := map[string]any{
			"kind":            "go-request-allocations",
			"path":            r.URL.Path,
			"events":          events,
			"mallocs":         after.Mallocs - before.Mallocs,
			"allocated_bytes": after.TotalAlloc - before.TotalAlloc,
		}
		encoded, _ := json.Marshal(result)
		log.Print(string(encoded))
	}
}

func workload(path string) (events int, payloadBytes int, delay time.Duration) {
	switch path {
	case "/hot-100":
		return 100, 256, 0
	case "/hot-1000":
		return 1000, 256, 0
	case "/hot-10000":
		return 10000, 256, 0
	case "/hot-4096":
		return 2000, 4096, 0
	case "/hot-65536":
		return 200, 65536, 0
	case "/idle":
		return 1_000_000, 256, 60 * time.Second
	default:
		return 1, 256, 0
	}
}

func htmlPayload(targetBytes, sequence int) string {
	prefix := `<article id="feed" data-seq="` + strconv.Itoa(sequence) + `"><p>`
	suffix := `</p></article>`
	padding := targetBytes - len(prefix) - len(suffix)
	if padding < 0 {
		padding = 0
	}
	return prefix + strings.Repeat("x", padding) + suffix
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
