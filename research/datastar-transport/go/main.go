package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/andybalholm/brotli"
	"github.com/starfederation/datastar-go/datastar"
)

type countingResponseWriter struct {
	header http.Header
	bytes  uint64
}

func newCountingResponseWriter() *countingResponseWriter {
	return &countingResponseWriter{header: make(http.Header)}
}

func (w *countingResponseWriter) Header() http.Header { return w.header }
func (w *countingResponseWriter) WriteHeader(_ int)   {}
func (w *countingResponseWriter) Write(p []byte) (int, error) {
	w.bytes += uint64(len(p))
	return len(p), nil
}
func (w *countingResponseWriter) Flush() {}

func datastarEvent(targetBytes, sequence int) []byte {
	prefix := fmt.Sprintf("event: datastar-patch-elements\ndata: selector #todos\ndata: mode replace\ndata: elements <ul data-seq=\"%d\">", sequence)
	suffix := "</ul>\n\n\n"
	row := "<li class=\"todo\"><span>write bounded streaming tests</span></li>"
	var event strings.Builder
	event.Grow(targetBytes + len(row))
	event.WriteString(prefix)
	for event.Len()+len(row)+len(suffix) < targetBytes {
		event.WriteString(row)
	}
	event.WriteString(suffix)
	return []byte(event.String())
}

func htmlPayload(targetBytes, sequence int) string {
	prefix := fmt.Sprintf("<ul data-seq=\"%d\">", sequence)
	suffix := "</ul>"
	row := "<li class=\"todo\"><span>write bounded streaming tests</span></li>"
	var html strings.Builder
	// Datastar framing around this one-line HTML payload is 94 bytes for these
	// selector/mode options in v1.2.2.
	html.Grow(targetBytes)
	html.WriteString(prefix)
	for html.Len()+len(row)+len(suffix)+94 < targetBytes {
		html.WriteString(row)
	}
	html.WriteString(suffix)
	return html.String()
}

type sample struct {
	Implementation    string  `json:"implementation"`
	Evidence          string  `json:"evidence"`
	Mode              string  `json:"mode"`
	Quality           int     `json:"quality"`
	WindowBits        int     `json:"window_bits"`
	TargetEventBytes  int     `json:"target_event_bytes"`
	FramedEventBytes  int     `json:"framed_event_bytes"`
	Events            int     `json:"events"`
	Sample            int     `json:"sample"`
	ElapsedNS         int64   `json:"elapsed_ns"`
	NSPerEvent        float64 `json:"ns_per_event"`
	InputBytes        uint64  `json:"input_bytes"`
	WireBytes         uint64  `json:"wire_bytes"`
	CompressionRatio  float64 `json:"compression_ratio"`
	AllocationCalls   uint64  `json:"allocation_calls"`
	AllocatedBytes    uint64  `json:"allocated_bytes"`
	RetainedHeapBytes int64   `json:"retained_heap_bytes"`
	CleanFinish       bool    `json:"clean_finish"`
}

func eventCount(target int) int {
	count := (64 * 1024 * 1024) / target
	if count < 1000 {
		return 1000
	}
	return count
}

func readMemory() runtime.MemStats {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return stats
}

func directRun(event []byte, events int) (uint64, error) {
	wire := newCountingResponseWriter()
	encoder := brotli.NewWriterOptions(wire, brotli.WriterOptions{Quality: 4, LGWin: 18})
	for range events {
		if _, err := encoder.Write(event); err != nil {
			return 0, err
		}
		if err := encoder.Flush(); err != nil {
			return 0, err
		}
	}
	if err := encoder.Close(); err != nil {
		return 0, err
	}
	return wire.bytes, nil
}

func sdkRun(html string, events int, semantic bool) (uint64, error) {
	wire := newCountingResponseWriter()
	request := httptest.NewRequest(http.MethodGet, "/events", nil)
	request.Header.Set("Accept-Encoding", "br")
	options := []datastar.SSEOption{datastar.WithCompression()}
	if semantic {
		options = []datastar.SSEOption{datastar.WithCompression(
			datastar.WithBrotli(
				datastar.WithBrotliLevel(4),
				datastar.WithBrotliLGWin(18),
			),
			datastar.WithForced(),
		)}
	}
	sse := datastar.NewSSE(wire, request, options...)
	for range events {
		if err := sse.PatchElements(
			html,
			datastar.WithSelector("#todos"),
			datastar.WithMode(datastar.ElementPatchModeReplace),
		); err != nil {
			return 0, err
		}
	}
	// ServerSentEventGenerator exposes no Close method. The configured writer is
	// flushed per event but its Brotli FINISH operation cannot be requested.
	runtime.KeepAlive(sse)
	return wire.bytes, nil
}

func benchmark(samples int) error {
	encoder := json.NewEncoder(os.Stdout)
	for _, target := range []int{256, 4096, 65536} {
		event := datastarEvent(target, 1)
		html := htmlPayload(target, 1)
		events := eventCount(target)
		if _, err := directRun(event, min(events, 100)); err != nil {
			return err
		}
		if _, err := sdkRun(html, min(events, 100), true); err != nil {
			return err
		}
		if _, err := sdkRun(html, min(events, 100), false); err != nil {
			return err
		}

		implementations := []struct {
			name        string
			mode        string
			quality     int
			window      int
			framedBytes int
			cleanFinish bool
			run         func() (uint64, error)
		}{
			{
				name:        "go-andybalholm-q4-w18",
				mode:        "semantic-equivalence-compressor",
				quality:     4,
				window:      18,
				framedBytes: len(event),
				cleanFinish: true,
				run:         func() (uint64, error) { return directRun(event, events) },
			},
			{
				name:        "go-datastar-sdk-q4-w18",
				mode:        "configured-sdk-no-finish",
				quality:     4,
				window:      18,
				framedBytes: len(event),
				cleanFinish: false,
				run:         func() (uint64, error) { return sdkRun(html, events, true) },
			},
			{
				name:        "go-datastar-sdk-default",
				mode:        "idiomatic-sdk-default-no-finish",
				quality:     6,
				window:      0,
				framedBytes: len(event),
				cleanFinish: false,
				run:         func() (uint64, error) { return sdkRun(html, events, false) },
			},
		}

		for _, implementation := range implementations {
			for sampleIndex := range samples {
				runtime.GC()
				before := readMemory()
				started := time.Now()
				wireBytes, err := implementation.run()
				if err != nil {
					return err
				}
				elapsed := time.Since(started)
				after := readMemory()
				inputBytes := uint64(implementation.framedBytes * events)
				result := sample{
					Implementation:    implementation.name,
					Evidence:          "measured",
					Mode:              implementation.mode,
					Quality:           implementation.quality,
					WindowBits:        implementation.window,
					TargetEventBytes:  target,
					FramedEventBytes:  implementation.framedBytes,
					Events:            events,
					Sample:            sampleIndex,
					ElapsedNS:         elapsed.Nanoseconds(),
					NSPerEvent:        float64(elapsed.Nanoseconds()) / float64(events),
					InputBytes:        inputBytes,
					WireBytes:         wireBytes,
					CompressionRatio:  float64(wireBytes) / float64(inputBytes),
					AllocationCalls:   after.Mallocs - before.Mallocs,
					AllocatedBytes:    after.TotalAlloc - before.TotalAlloc,
					RetainedHeapBytes: int64(after.HeapAlloc) - int64(before.HeapAlloc),
					CleanFinish:       implementation.cleanFinish,
				}
				if err := encoder.Encode(result); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

type memoryResult struct {
	Implementation         string  `json:"implementation"`
	Evidence               string  `json:"evidence"`
	Streams                int     `json:"streams"`
	EventBytes             int     `json:"event_bytes"`
	AllocationCalls        uint64  `json:"allocation_calls"`
	AllocatedBytes         uint64  `json:"allocated_bytes"`
	RetainedHeapBytes      int64   `json:"retained_heap_bytes"`
	RetainedBytesPerStream float64 `json:"retained_bytes_per_stream"`
}

func memory(implementation string, streams int) error {
	event := datastarEvent(256, 1)
	html := htmlPayload(256, 1)
	runtime.GC()
	before := readMemory()

	switch implementation {
	case "direct":
		encoders := make([]*brotli.Writer, 0, streams)
		writers := make([]*countingResponseWriter, 0, streams)
		for range streams {
			writer := newCountingResponseWriter()
			encoder := brotli.NewWriterOptions(writer, brotli.WriterOptions{Quality: 4, LGWin: 18})
			if _, err := encoder.Write(event); err != nil {
				return err
			}
			if err := encoder.Flush(); err != nil {
				return err
			}
			writers = append(writers, writer)
			encoders = append(encoders, encoder)
		}
		runtime.GC()
		after := readMemory()
		retained := int64(after.HeapAlloc) - int64(before.HeapAlloc)
		result := memoryResult{
			Implementation:         "go-andybalholm-q4-w18",
			Evidence:               "measured",
			Streams:                streams,
			EventBytes:             len(event),
			AllocationCalls:        after.Mallocs - before.Mallocs,
			AllocatedBytes:         after.TotalAlloc - before.TotalAlloc,
			RetainedHeapBytes:      retained,
			RetainedBytesPerStream: float64(retained) / float64(streams),
		}
		if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
			return err
		}
		runtime.KeepAlive(encoders)
		runtime.KeepAlive(writers)
	case "sdk-q4", "sdk-default":
		streamsLive := make([]*datastar.ServerSentEventGenerator, 0, streams)
		writers := make([]*countingResponseWriter, 0, streams)
		semantic := implementation == "sdk-q4"
		for range streams {
			writer := newCountingResponseWriter()
			request := httptest.NewRequest(http.MethodGet, "/events", nil)
			request.Header.Set("Accept-Encoding", "br")
			options := []datastar.SSEOption{datastar.WithCompression()}
			if semantic {
				options = []datastar.SSEOption{datastar.WithCompression(
					datastar.WithBrotli(
						datastar.WithBrotliLevel(4),
						datastar.WithBrotliLGWin(18),
					),
					datastar.WithForced(),
				)}
			}
			sse := datastar.NewSSE(writer, request, options...)
			if err := sse.PatchElements(
				html,
				datastar.WithSelector("#todos"),
				datastar.WithMode(datastar.ElementPatchModeReplace),
			); err != nil {
				return err
			}
			writers = append(writers, writer)
			streamsLive = append(streamsLive, sse)
		}
		runtime.GC()
		after := readMemory()
		retained := int64(after.HeapAlloc) - int64(before.HeapAlloc)
		name := "go-datastar-sdk-default"
		if semantic {
			name = "go-datastar-sdk-q4-w18"
		}
		result := memoryResult{
			Implementation:         name,
			Evidence:               "measured",
			Streams:                streams,
			EventBytes:             len(event),
			AllocationCalls:        after.Mallocs - before.Mallocs,
			AllocatedBytes:         after.TotalAlloc - before.TotalAlloc,
			RetainedHeapBytes:      retained,
			RetainedBytesPerStream: float64(retained) / float64(streams),
		}
		if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
			return err
		}
		runtime.KeepAlive(streamsLive)
		runtime.KeepAlive(writers)
	default:
		return fmt.Errorf("unknown memory implementation %q", implementation)
	}
	return nil
}

func main() {
	command := "benchmark"
	if len(os.Args) > 1 {
		command = os.Args[1]
	}
	if command == "memory" {
		if len(os.Args) != 4 {
			fmt.Fprintln(os.Stderr, "memory requires IMPLEMENTATION STREAMS")
			os.Exit(2)
		}
		streams, err := strconv.Atoi(os.Args[3])
		if err != nil || streams < 1 {
			fmt.Fprintln(os.Stderr, "streams must be a positive integer")
			os.Exit(2)
		}
		if err := memory(os.Args[2], streams); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if command != "benchmark" {
		fmt.Fprintf(os.Stderr, "unknown command %q\n", command)
		os.Exit(2)
	}
	samples := 7
	if len(os.Args) > 2 {
		value, err := strconv.Atoi(os.Args[2])
		if err != nil || value < 1 {
			fmt.Fprintln(os.Stderr, "samples must be a positive integer")
			os.Exit(2)
		}
		samples = value
	}
	if err := benchmark(samples); err != nil && err != io.EOF {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
