package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/andybalholm/brotli"
)

type trace struct {
	name       string
	events     [][]byte
	inputBytes int
	digest     uint64
}

func newTrace(name string, events [][]byte) trace {
	inputBytes := 0
	digest := uint64(0xcbf29ce484222325)
	for _, event := range events {
		inputBytes += len(event)
		for _, value := range event {
			digest = (digest ^ uint64(value)) * 0x100000001b3
		}
	}
	return trace{name: name, events: events, inputBytes: inputBytes, digest: digest}
}

func todoTrace() trace {
	events := make([][]byte, 0, 512)
	for sequence := range 512 {
		var event strings.Builder
		fmt.Fprintf(&event, "event: datastar-patch-elements\ndata: selector #todos\ndata: mode replace\ndata: elements <ul id=\"todos\" data-version=\"%d\">", sequence)
		for row := range 24 {
			id := (sequence + row*17) % 997
			completed := (sequence+row)%5 == 0
			priority := []string{"low", "normal", "high"}[(sequence+row)%3]
			state := ""
			checked := ""
			if completed {
				state = " done"
				checked = " checked"
			}
			fmt.Fprintf(&event, "<li id=\"todo-%d\" class=\"todo%s\" data-priority=\"%s\"><input type=\"checkbox\"%s><span>Task %d: validate bounded progressive delivery</span><small>%d/%d</small></li>", id, state, priority, checked, id, sequence%31, 31)
		}
		event.WriteString("</ul>\n\n")
		events = append(events, []byte(event.String()))
	}
	return newTrace("changing-todo-html", events)
}

func dashboardTrace() trace {
	events := make([][]byte, 0, 512)
	regions := []string{"mel", "syd", "sin", "fra"}
	for sequence := range 512 {
		if sequence%7 == 0 {
			events = append(events, []byte(fmt.Sprintf(
				"event: datastar-patch-signals\ndata: signals {\"active\":%d,\"queued\":%d,\"p95Ms\":%d,\"region\":\"%s\"}\n\n",
				80+sequence%37, sequence%19, 11+sequence%23, regions[sequence%4],
			)))
			continue
		}
		var event strings.Builder
		fmt.Fprintf(&event, "event: datastar-patch-elements\ndata: selector #dashboard\ndata: mode replace\ndata: elements <section id=\"dashboard\" data-sample=\"%d\"><header><h2>Live operations</h2><time>2026-08-01T12:%02d:%02d+10:00</time></header><table>", sequence, (sequence/60)%60, sequence%60)
		for row := range 18 {
			value := (sequence*97 + row*43) % 10000
			fmt.Fprintf(&event, "<tr data-service=\"svc-%d\"><th>service-%02d</th><td>%d</td><td>%.2f%%</td><td><meter min=\"0\" max=\"100\" value=\"%d\"></meter></td></tr>", row, row, value, float64(value%1000)/100.0, value%101)
		}
		event.WriteString("</table></section>\n\n")
		events = append(events, []byte(event.String()))
	}
	return newTrace("changing-dashboard-mixed", events)
}

func heartbeatTrace() trace {
	events := make([][]byte, 512)
	for index := range events {
		events[index] = []byte(": keepalive\n\n")
	}
	return newTrace("heartbeat-only", events)
}

func largeHTMLTrace() trace {
	events := make([][]byte, 0, 128)
	zones := []string{"mel", "syd", "sin", "fra"}
	for sequence := range 128 {
		var event strings.Builder
		fmt.Fprintf(&event, "event: datastar-patch-elements\ndata: selector #catalog\ndata: mode replace\ndata: elements <section id=\"catalog\" data-version=\"%d\">", sequence)
		for row := 0; ; row++ {
			id := sequence*10000 + row
			candidate := fmt.Sprintf(
				"<article id=\"item-%d\" data-stock=\"%d\" data-zone=\"%s\"><h3>Inventory item %d</h3><p>Changing description token %d for bounded Datastar patch validation.</p><strong>$%d.%02d</strong></article>",
				id,
				(sequence*37+row*19)%251,
				zones[row%4],
				id,
				(sequence*7919+row*104729)%1000003,
				(sequence*97+row*43)%500,
				(sequence+row*7)%100,
			)
			if event.Len()+len(candidate)+len("</section>\n\n") > 65536 {
				break
			}
			event.WriteString(candidate)
		}
		event.WriteString("</section>\n\n")
		events = append(events, []byte(event.String()))
	}
	return newTrace("changing-64k-html", events)
}

func selectTrace(name string) trace {
	switch name {
	case "todo":
		return todoTrace()
	case "dashboard":
		return dashboardTrace()
	case "heartbeat":
		return heartbeatTrace()
	case "large":
		return largeHTMLTrace()
	default:
		panic(fmt.Sprintf("unknown trace %q", name))
	}
}

type countingWriter struct {
	bytes uint64
}

func (writer *countingWriter) Write(data []byte) (int, error) {
	writer.bytes += uint64(len(data))
	return len(data), nil
}

type benchmarkResult struct {
	Implementation   string  `json:"implementation"`
	Evidence         string  `json:"evidence"`
	Quality          int     `json:"quality"`
	WindowBits       int     `json:"window_bits"`
	Trace            string  `json:"trace"`
	TraceDigest      string  `json:"trace_digest_fnv64"`
	Cycles           int     `json:"cycles"`
	Events           int     `json:"events"`
	InputBytes       uint64  `json:"input_bytes"`
	WireBytes        uint64  `json:"wire_bytes"`
	CompressionRatio float64 `json:"compression_ratio"`
	ElapsedNS        int64   `json:"elapsed_ns"`
	NSPerEvent       float64 `json:"ns_per_event"`
	FlushP50NS       int64   `json:"flush_p50_ns"`
	FlushP95NS       int64   `json:"flush_p95_ns"`
	FlushP99NS       int64   `json:"flush_p99_ns"`
	FlushMaxNS       int64   `json:"flush_max_ns"`
	AllocationCalls  uint64  `json:"allocation_calls"`
	AllocatedBytes   uint64  `json:"allocated_bytes"`
	CallsPerEvent    float64 `json:"allocation_calls_per_event"`
	BytesPerEvent    float64 `json:"allocated_bytes_per_event"`
}

func readMemory() runtime.MemStats {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return stats
}

func percentile(values []int64, percentile int) int64 {
	return values[(len(values)-1)*percentile/100]
}

func runSample(quality, windowBits int, input trace, targetMiB int) (benchmarkResult, error) {
	targetBytes := targetMiB * 1024 * 1024
	cycles := max(1, (targetBytes+input.inputBytes-1)/input.inputBytes)
	events := cycles * len(input.events)
	latencies := make([]int64, 0, events)
	runtime.GC()
	before := readMemory()
	started := time.Now()
	wire := &countingWriter{}
	encoder := brotli.NewWriterOptions(wire, brotli.WriterOptions{Quality: quality, LGWin: windowBits})
	for range cycles {
		for _, event := range input.events {
			flushStarted := time.Now()
			if _, err := encoder.Write(event); err != nil {
				return benchmarkResult{}, err
			}
			if err := encoder.Flush(); err != nil {
				return benchmarkResult{}, err
			}
			latencies = append(latencies, time.Since(flushStarted).Nanoseconds())
		}
	}
	if err := encoder.Close(); err != nil {
		return benchmarkResult{}, err
	}
	elapsed := time.Since(started)
	after := readMemory()
	sort.Slice(latencies, func(left, right int) bool { return latencies[left] < latencies[right] })
	inputBytes := uint64(input.inputBytes * cycles)
	return benchmarkResult{
		Implementation:   "go-andybalholm",
		Evidence:         "measured-go-runtime",
		Quality:          quality,
		WindowBits:       windowBits,
		Trace:            input.name,
		TraceDigest:      fmt.Sprintf("%016x", input.digest),
		Cycles:           cycles,
		Events:           events,
		InputBytes:       inputBytes,
		WireBytes:        wire.bytes,
		CompressionRatio: float64(wire.bytes) / float64(inputBytes),
		ElapsedNS:        elapsed.Nanoseconds(),
		NSPerEvent:       float64(elapsed.Nanoseconds()) / float64(events),
		FlushP50NS:       percentile(latencies, 50),
		FlushP95NS:       percentile(latencies, 95),
		FlushP99NS:       percentile(latencies, 99),
		FlushMaxNS:       latencies[len(latencies)-1],
		AllocationCalls:  after.Mallocs - before.Mallocs,
		AllocatedBytes:   after.TotalAlloc - before.TotalAlloc,
		CallsPerEvent:    float64(after.Mallocs-before.Mallocs) / float64(events),
		BytesPerEvent:    float64(after.TotalAlloc-before.TotalAlloc) / float64(events),
	}, nil
}

type memoryResult struct {
	Implementation         string  `json:"implementation"`
	Evidence               string  `json:"evidence"`
	Quality                int     `json:"quality"`
	WindowBits             int     `json:"window_bits"`
	Trace                  string  `json:"trace"`
	Streams                int     `json:"streams"`
	ActivationEvents       int     `json:"activation_events_per_stream"`
	HeapLiveAllocations    uint64  `json:"heap_live_allocations"`
	HeapBytes              int64   `json:"heap_bytes"`
	HeapBytesPerStream     float64 `json:"heap_bytes_per_stream"`
	Projected1kMiB         float64 `json:"projected_1k_mib"`
	Projected10kGiB        float64 `json:"projected_10k_gib"`
	ConstructionAllocCalls uint64  `json:"construction_allocation_calls"`
	ConstructionAllocBytes uint64  `json:"construction_allocated_bytes"`
}

func memory(quality, windowBits, streams, activationEvents int, input trace) (memoryResult, error) {
	encoders := make([]*brotli.Writer, 0, streams)
	writers := make([]*countingWriter, 0, streams)
	runtime.GC()
	before := readMemory()
	for index := range streams {
		writer := &countingWriter{}
		encoder := brotli.NewWriterOptions(writer, brotli.WriterOptions{Quality: quality, LGWin: windowBits})
		for eventIndex := range activationEvents {
			if _, err := encoder.Write(input.events[(index+eventIndex)%len(input.events)]); err != nil {
				return memoryResult{}, err
			}
			if err := encoder.Flush(); err != nil {
				return memoryResult{}, err
			}
		}
		writers = append(writers, writer)
		encoders = append(encoders, encoder)
	}
	runtime.GC()
	after := readMemory()
	retained := int64(after.HeapAlloc) - int64(before.HeapAlloc)
	perStream := float64(retained) / float64(streams)
	result := memoryResult{
		Implementation:         "go-andybalholm",
		Evidence:               "measured-go-runtime-after-gc",
		Quality:                quality,
		WindowBits:             windowBits,
		Trace:                  input.name,
		Streams:                streams,
		ActivationEvents:       activationEvents,
		HeapLiveAllocations:    after.Mallocs - after.Frees - (before.Mallocs - before.Frees),
		HeapBytes:              retained,
		HeapBytesPerStream:     perStream,
		Projected1kMiB:         perStream * 1000 / (1024 * 1024),
		Projected10kGiB:        perStream * 10000 / (1024 * 1024 * 1024),
		ConstructionAllocCalls: after.Mallocs - before.Mallocs,
		ConstructionAllocBytes: after.TotalAlloc - before.TotalAlloc,
	}
	runtime.KeepAlive(encoders)
	runtime.KeepAlive(writers)
	return result, nil
}

type steadyResult struct {
	Implementation     string `json:"implementation"`
	Quality            int    `json:"quality"`
	WindowBits         int    `json:"window_bits"`
	Trace              string `json:"trace"`
	WarmupEvents       int    `json:"warmup_events"`
	MeasuredEvents     int    `json:"measured_events"`
	AllocationCalls    uint64 `json:"allocation_calls"`
	AllocatedBytes     uint64 `json:"allocated_bytes"`
	LiveHeapBytesDelta int64  `json:"live_heap_bytes_delta"`
}

func steady(quality, windowBits int, input trace, measuredEvents int) (steadyResult, error) {
	const warmupEvents = 2048
	wire := &countingWriter{}
	encoder := brotli.NewWriterOptions(wire, brotli.WriterOptions{Quality: quality, LGWin: windowBits})
	for index := range warmupEvents {
		if _, err := encoder.Write(input.events[index%len(input.events)]); err != nil {
			return steadyResult{}, err
		}
		if err := encoder.Flush(); err != nil {
			return steadyResult{}, err
		}
	}
	runtime.GC()
	before := readMemory()
	for index := range measuredEvents {
		if _, err := encoder.Write(input.events[index%len(input.events)]); err != nil {
			return steadyResult{}, err
		}
		if err := encoder.Flush(); err != nil {
			return steadyResult{}, err
		}
	}
	after := readMemory()
	result := steadyResult{
		Implementation:     "go-andybalholm",
		Quality:            quality,
		WindowBits:         windowBits,
		Trace:              input.name,
		WarmupEvents:       warmupEvents,
		MeasuredEvents:     measuredEvents,
		AllocationCalls:    after.Mallocs - before.Mallocs,
		AllocatedBytes:     after.TotalAlloc - before.TotalAlloc,
		LiveHeapBytesDelta: int64(after.HeapAlloc) - int64(before.HeapAlloc),
	}
	runtime.KeepAlive(encoder)
	return result, nil
}

func integer(value, name string) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		panic(fmt.Sprintf("invalid %s", name))
	}
	return parsed
}

func emit(value any, err error) {
	if err != nil {
		panic(err)
	}
	if err := json.NewEncoder(os.Stdout).Encode(value); err != nil {
		panic(err)
	}
}

func main() {
	if len(os.Args) < 2 {
		panic("missing command")
	}
	switch os.Args[1] {
	case "run":
		if len(os.Args) != 7 {
			panic("usage: footprint run Q W TRACE SAMPLES MIB")
		}
		quality, windowBits := integer(os.Args[2], "quality"), integer(os.Args[3], "window bits")
		input := selectTrace(os.Args[4])
		for range integer(os.Args[5], "samples") {
			emit(runSample(quality, windowBits, input, integer(os.Args[6], "target MiB")))
		}
	case "screen":
		if len(os.Args) != 3 && len(os.Args) != 4 {
			panic("usage: footprint screen TRACE [MIB]")
		}
		input := selectTrace(os.Args[2])
		targetMiB := 2
		if len(os.Args) == 4 {
			targetMiB = integer(os.Args[3], "target MiB")
		}
		for quality := 0; quality <= 6; quality++ {
			for windowBits := 10; windowBits <= 18; windowBits++ {
				emit(runSample(quality, windowBits, input, targetMiB))
			}
		}
	case "memory":
		if len(os.Args) != 6 && len(os.Args) != 7 {
			panic("usage: footprint memory Q W STREAMS TRACE [ACTIVATION_EVENTS]")
		}
		activationEvents := 1
		if len(os.Args) == 7 {
			activationEvents = integer(os.Args[6], "activation events")
		}
		emit(memory(integer(os.Args[2], "quality"), integer(os.Args[3], "window bits"), integer(os.Args[4], "streams"), activationEvents, selectTrace(os.Args[5])))
	case "steady":
		if len(os.Args) != 6 {
			panic("usage: footprint steady Q W TRACE EVENTS")
		}
		emit(steady(integer(os.Args[2], "quality"), integer(os.Args[3], "window bits"), selectTrace(os.Args[4]), integer(os.Args[5], "events")))
	default:
		panic("unknown command")
	}
}

var _ io.Writer = (*countingWriter)(nil)
