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
	streamSlots        = make(chan struct{}, 128)
)

func main() {
	flag.Parse()
	http.HandleFunc("/finite", finite)
	http.HandleFunc("/progressive", progressive)
	http.HandleFunc("/persistent", persistent)
	http.HandleFunc("/ordinary", ordinary)
	for _, route := range []string{
		"/hot-100", "/hot-1000", "/hot-10000", "/hot-4096", "/hot-65536",
		"/repeat-100", "/repeat-1000", "/repeat-256", "/repeat-4096", "/repeat-65536",
		"/assemble-100", "/assemble-1000", "/assemble-256", "/assemble-4096", "/assemble-65536",
		"/transport-100", "/transport-1000", "/transport-256", "/transport-4096", "/transport-65536", "/idle", "/wake-100",
	} {
		http.HandleFunc(route, fixedWorkload)
	}
	log.Printf("Go Datastar reference listening on http://%s (%s)", *address, *coding)
	log.Fatal(http.ListenAndServe(*address, nil))
}

func admitStream(w http.ResponseWriter) bool {
	select {
	case streamSlots <- struct{}{}:
		return true
	default:
		http.Error(w, "Server is overloaded", http.StatusServiceUnavailable)
		return false
	}
}

func releaseStream() { <-streamSlots }

func ordinary(w http.ResponseWriter, _ *http.Request) {
	_, _ = w.Write([]byte("ok"))
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
	if !admitStream(w) {
		return
	}
	defer releaseStream()
	_ = stream(w, r).PatchElements(htmlPayload(256, 1))
}

func progressive(w http.ResponseWriter, r *http.Request) {
	if !admitStream(w) {
		return
	}
	defer releaseStream()
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
	if !admitStream(w) {
		return
	}
	defer releaseStream()
	events, payloadBytes, delay := workload(r.URL.Path)
	var before runtime.MemStats
	if *measureAllocations {
		runtime.GC()
		runtime.ReadMemStats(&before)
	}

	sse := stream(w, r)
	preparedHTML := ""
	preparedPadding := ""
	if strings.HasPrefix(r.URL.Path, "/transport-") {
		preparedHTML = htmlPayload(payloadBytes, 1)
	} else if strings.HasPrefix(r.URL.Path, "/assemble-") {
		preparedPadding = payloadPadding(payloadBytes, 1)
	}
	for sequence := 1; sequence <= events; sequence++ {
		html := preparedHTML
		if strings.HasPrefix(r.URL.Path, "/repeat-") {
			html = strings.Repeat("x", payloadBytes)
		} else if preparedPadding != "" {
			html = htmlPayloadWithPadding(preparedPadding, sequence)
		} else if html == "" {
			html = htmlPayload(payloadBytes, sequence)
		}
		if err := sse.PatchElements(html); err != nil {
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
	case "/hot-100", "/repeat-100", "/assemble-100":
		return 100, 256, 0
	case "/hot-1000", "/repeat-1000", "/assemble-1000":
		return 1000, 256, 0
	case "/transport-100":
		return 100, 256, 0
	case "/transport-1000":
		return 1000, 256, 0
	case "/hot-10000", "/repeat-256", "/assemble-256":
		return 10000, 256, 0
	case "/hot-4096", "/repeat-4096", "/assemble-4096", "/transport-4096":
		return 2000, 4096, 0
	case "/hot-65536", "/repeat-65536", "/assemble-65536", "/transport-65536":
		return 200, 65536, 0
	case "/transport-256":
		return 10000, 256, 0
	case "/idle":
		return 1_000_000, 256, 60 * time.Second
	case "/wake-100":
		return 2, 256, 100 * time.Millisecond
	default:
		return 1, 256, 0
	}
}

func htmlPayload(targetBytes, sequence int) string {
	return htmlPayloadWithPadding(payloadPadding(targetBytes, sequence), sequence)
}

func payloadPadding(targetBytes, sequence int) string {
	prefix := `<article id="feed" data-seq="` + strconv.Itoa(sequence) + `"><p>`
	suffix := `</p></article>`
	padding := targetBytes - len(prefix) - len(suffix)
	if padding < 0 {
		padding = 0
	}
	return strings.Repeat("x", padding)
}

func htmlPayloadWithPadding(padding string, sequence int) string {
	prefix := `<article id="feed" data-seq="` + strconv.Itoa(sequence) + `"><p>`
	suffix := `</p></article>`
	return prefix + padding + suffix
}

func persistent(w http.ResponseWriter, r *http.Request) {
	if !admitStream(w) {
		return
	}
	defer releaseStream()
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
