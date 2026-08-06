package goreference

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/andybalholm/brotli"
	"github.com/starfederation/datastar-go/datastar"
)

type coding int

const (
	identity coding = iota
	idiomaticBrotli
	equivalentBrotli
)

type observingWriter struct {
	header  http.Header
	body    bytes.Buffer
	status  int
	flushes int
}

func (w *observingWriter) Header() http.Header {
	if w.header == nil {
		w.header = make(http.Header)
	}
	return w.header
}

func (w *observingWriter) Write(p []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	return w.body.Write(p)
}

func (w *observingWriter) WriteHeader(status int) { w.status = status }
func (w *observingWriter) Flush()                 { w.flushes++ }

type countingWriter struct {
	header  http.Header
	bytes   int64
	status  int
	flushes int
}

func (w *countingWriter) Header() http.Header {
	if w.header == nil {
		w.header = make(http.Header)
	}
	return w.header
}

func (w *countingWriter) Write(p []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	w.bytes += int64(len(p))
	return len(p), nil
}

func (w *countingWriter) WriteHeader(status int) { w.status = status }
func (w *countingWriter) Flush()                 { w.flushes++ }

func newSSE(w http.ResponseWriter, r *http.Request, selected coding) *datastar.ServerSentEventGenerator {
	switch selected {
	case identity:
		return datastar.NewSSE(w, r)
	case idiomaticBrotli:
		return datastar.NewSSE(w, r, datastar.WithCompression())
	case equivalentBrotli:
		return datastar.NewSSE(w, r, datastar.WithCompression(
			datastar.WithBrotli(datastar.WithBrotliLevel(4), datastar.WithBrotliLGWin(18)),
			datastar.WithForced(),
		))
	default:
		panic("unknown coding")
	}
}

func request(protoMajor int, acceptEncoding string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "http://example.test/events", nil)
	r.ProtoMajor = protoMajor
	r.Header.Set("Accept-Encoding", acceptEncoding)
	return r
}

func TestStableGoSDKWireAndHeaderObservations(t *testing.T) {
	t.Run("identity framing has one extra LF compared with client golden", func(t *testing.T) {
		w := &observingWriter{}
		sse := newSSE(w, request(1, ""), identity)
		if err := sse.PatchElements("<div>Merge</div>"); err != nil {
			t.Fatal(err)
		}
		golden := "event: datastar-patch-elements\ndata: elements <div>Merge</div>\n\n"
		if got, want := w.body.String(), golden+"\n"; got != want {
			t.Fatalf("stable SDK behavior changed\ngot  %q\nwant %q", got, want)
		}
		if got := w.Header().Get("Connection"); got != "keep-alive" {
			t.Fatalf("HTTP/1 Connection = %q", got)
		}
		if got := w.flushes; got != 2 {
			t.Fatalf("flush calls = %d, want header + event", got)
		}
	})

	t.Run("HTTP2 omits Connection", func(t *testing.T) {
		w := &observingWriter{}
		_ = newSSE(w, request(2, ""), identity)
		if got := w.Header().Get("Connection"); got != "" {
			t.Fatalf("HTTP/2 Connection = %q", got)
		}
	})

	t.Run("compression is opt in", func(t *testing.T) {
		w := &observingWriter{}
		_ = newSSE(w, request(1, "br"), identity)
		if got := w.Header().Get("Content-Encoding"); got != "" {
			t.Fatalf("Content-Encoding = %q", got)
		}
	})

	t.Run("q zero is treated as accepted", func(t *testing.T) {
		w := &observingWriter{}
		_ = newSSE(w, request(1, "br;q=0"), idiomaticBrotli)
		if got := w.Header().Get("Content-Encoding"); got != "br" {
			t.Fatalf("Content-Encoding = %q, want observed br", got)
		}
	})

	t.Run("wildcard is not matched and Vary is absent", func(t *testing.T) {
		w := &observingWriter{}
		_ = newSSE(w, request(1, "*"), idiomaticBrotli)
		if got := w.Header().Get("Content-Encoding"); got != "" {
			t.Fatalf("Content-Encoding = %q", got)
		}
		if got := w.Header().Values("Vary"); len(got) != 0 {
			t.Fatalf("Vary = %q", got)
		}
	})

	t.Run("server priority ignores q ranking", func(t *testing.T) {
		w := &observingWriter{}
		_ = newSSE(w, request(1, "gzip;q=1, br;q=0.1"), idiomaticBrotli)
		if got := w.Header().Get("Content-Encoding"); got != "br" {
			t.Fatalf("Content-Encoding = %q, want server-first br", got)
		}
	})

	t.Run("compression overwrites no-transform", func(t *testing.T) {
		w := &observingWriter{header: http.Header{"Cache-Control": {"private, no-transform"}}}
		_ = newSSE(w, request(1, "br"), idiomaticBrotli)
		if got := w.Header().Get("Cache-Control"); got != "no-cache" {
			t.Fatalf("Cache-Control = %q, want observed overwrite", got)
		}
		if got := w.Header().Get("Content-Encoding"); got != "br" {
			t.Fatalf("Content-Encoding = %q", got)
		}
	})

	t.Run("event fields are emitted without injection validation", func(t *testing.T) {
		w := &observingWriter{}
		sse := newSSE(w, request(1, ""), identity)
		if err := sse.Send(
			datastar.EventType("custom\ndata: injected"),
			[]string{"safe\ndata: second-injected"},
			datastar.WithSSEEventId("cursor\nid: replaced"),
		); err != nil {
			t.Fatal(err)
		}
		for _, injected := range []string{"data: injected", "id: replaced", "data: second-injected"} {
			if !strings.Contains(w.body.String(), injected) {
				t.Fatalf("missing injected field %q in %q", injected, w.body.String())
			}
		}
	})
}

func TestProgressiveDelivery(t *testing.T) {
	for _, tc := range []struct {
		name   string
		coding coding
	}{
		{name: "identity", coding: identity},
		{name: "brotli-equivalent", coding: equivalentBrotli},
	} {
		t.Run(tc.name, func(t *testing.T) {
			firstSent := make(chan struct{})
			allowSecond := make(chan struct{})
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				sse := newSSE(w, r, tc.coding)
				if err := sse.PatchElements(`<div id="stage">one</div>`); err != nil {
					return
				}
				close(firstSent)
				select {
				case <-allowSecond:
				case <-r.Context().Done():
					return
				}
				_ = sse.PatchElements(`<div id="stage">two</div>`)
			}))
			defer server.Close()

			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			req, err := http.NewRequestWithContext(ctx, http.MethodGet, server.URL, nil)
			if err != nil {
				t.Fatal(err)
			}
			req.Header.Set("Accept-Encoding", "br")
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatal(err)
			}
			defer resp.Body.Close()

			var body io.Reader = resp.Body
			if tc.coding != identity {
				if got := resp.Header.Get("Content-Encoding"); got != "br" {
					t.Fatalf("Content-Encoding = %q", got)
				}
				body = brotli.NewReader(body)
			}
			reader := bufio.NewReader(body)
			<-firstSent
			if got := readEvent(t, reader); !strings.Contains(got, `id="stage">one`) {
				t.Fatalf("first event = %q", got)
			}
			close(allowSecond)
			if got := readEvent(t, reader); !strings.Contains(got, `id="stage">two`) {
				t.Fatalf("second event = %q", got)
			}
		})
	}
}

func TestStableGoSDKBrotliStreamIsNotFinished(t *testing.T) {
	w := &observingWriter{}
	sse := newSSE(w, request(1, "br"), equivalentBrotli)
	if err := sse.PatchElements(`<div id="stage">one</div>`); err != nil {
		t.Fatal(err)
	}
	decoded, err := io.ReadAll(brotli.NewReader(bytes.NewReader(w.body.Bytes())))
	if err == nil {
		t.Fatalf("stable SDK unexpectedly produced a finished Brotli stream: %q", decoded)
	}
	if !strings.Contains(string(decoded), `id="stage">one`) {
		t.Fatalf("flushed prefix was not decodable: %q (error %v)", decoded, err)
	}
}

func readEvent(t *testing.T, r *bufio.Reader) string {
	t.Helper()
	var lines []string
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			t.Fatalf("read event: %v", err)
		}
		line = strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r")
		if line == "" {
			if len(lines) == 0 {
				continue
			}
			return strings.Join(lines, "\n")
		}
		lines = append(lines, line)
	}
}

func BenchmarkOfficialSDKFinite(b *testing.B) {
	for _, size := range []int{256, 4 << 10, 64 << 10} {
		payload := htmlPatch(size)
		for _, tc := range []struct {
			name   string
			coding coding
		}{
			{name: "identity", coding: identity},
			{name: "brotli-idiomatic", coding: idiomaticBrotli},
			{name: "brotli-equivalent-q4-w18", coding: equivalentBrotli},
		} {
			b.Run(fmt.Sprintf("%s/%d", tc.name, size), func(b *testing.B) {
				b.ReportAllocs()
				b.SetBytes(int64(len(payload)))
				var wireBytes int64
				for range b.N {
					w := &countingWriter{}
					sse := newSSE(w, request(1, "br"), tc.coding)
					if err := sse.PatchElements(payload); err != nil {
						b.Fatal(err)
					}
					wireBytes += w.bytes
				}
				b.ReportMetric(float64(wireBytes)/float64(b.N), "wire-B/response")
			})
		}
	}
}

func BenchmarkOfficialSDKPersistent(b *testing.B) {
	for _, size := range []int{256, 4 << 10} {
		payload := htmlPatch(size)
		for _, tc := range []struct {
			name   string
			coding coding
		}{
			{name: "identity", coding: identity},
			{name: "brotli-idiomatic", coding: idiomaticBrotli},
			{name: "brotli-equivalent-q4-w18", coding: equivalentBrotli},
		} {
			b.Run(fmt.Sprintf("%s/%d", tc.name, size), func(b *testing.B) {
				w := &countingWriter{}
				sse := newSSE(w, request(1, "br"), tc.coding)
				b.ReportAllocs()
				b.SetBytes(int64(len(payload)))
				b.ResetTimer()
				for range b.N {
					if err := sse.PatchElements(payload); err != nil {
						b.Fatal(err)
					}
				}
				b.StopTimer()
				b.ReportMetric(float64(w.bytes)/float64(b.N), "wire-B/event")
			})
		}
	}
}

func htmlPatch(size int) string {
	prefix := `<article id="feed"><h2>Datastar update</h2><p>`
	suffix := `</p></article>`
	if size < len(prefix)+len(suffix) {
		panic("fixture size too small")
	}
	return prefix + strings.Repeat("repeated dashboard content ", (size-len(prefix)-len(suffix))/27+1)[:size-len(prefix)-len(suffix)] + suffix
}
