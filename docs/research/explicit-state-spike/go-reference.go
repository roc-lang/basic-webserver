package main

import (
	"fmt"
	"os"
	"runtime"
	"strconv"
	"time"
	"unsafe"
)

type state struct {
	checksum uint64
	items    []string
	label    string
	steps    uint64
	padding  [16]byte
}

var sink *state

func newState(seed uint64) *state {
	return &state{
		checksum: seed,
		items: []string{
			"first retained benchmark string crossing every state step",
			"second retained benchmark string crossing every state step",
		},
		label: "benchmark state carries nested values across every transition",
	}
}

//go:noinline
func roundtrip(current *state) *state {
	return current
}

// stepUnique models the best implementation allowed by transfer-only ownership:
// the caller has transferred the only mutable reference, so the state storage is
// reused and returned to the caller.
//
//go:noinline
func stepUnique(current *state, wake, eventCount uint64) *state {
	for index := uint64(0); index < eventCount; index++ {
		current.steps++
		current.checksum = current.checksum*6364136223846793005 + wake + index + current.steps
	}
	return current
}

// stepReplace is a diagnostic matching the current Roc lowering more literally:
// it allocates a replacement state even though the input is uniquely owned.
//
//go:noinline
func stepReplace(current *state, wake, eventCount uint64) *state {
	next := &state{
		checksum: current.checksum,
		items:    current.items,
		label:    current.label,
		steps:    current.steps,
	}
	for index := uint64(0); index < eventCount; index++ {
		next.steps++
		next.checksum = next.checksum*6364136223846793005 + wake + index + next.steps
	}
	return next
}

func positiveEnv(name string, fallback, minimum int) int {
	raw := os.Getenv(name)
	if raw == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(raw)
	if err != nil || parsed < minimum {
		panic("invalid " + name)
	}
	return parsed
}

func allocationCountRoundtrip(iterations int) {
	current := newState(141)
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	for index := 0; index < iterations; index++ {
		current = roundtrip(current)
	}
	runtime.ReadMemStats(&after)
	sink = current
	allocations := after.Mallocs - before.Mallocs
	fmt.Printf("ALLOC impl=go operation=roundtrip batch=0 steps=%d allocs_per_step=%.6f\n",
		iterations, float64(allocations)/float64(iterations))
}

func allocationCountTransition(operation string, iterations int, batch uint64) {
	current := newState(141)
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	if operation == "unique" {
		for index := 0; index < iterations; index++ {
			current = stepUnique(current, uint64(index&7), batch)
		}
	} else {
		for index := 0; index < iterations; index++ {
			current = stepReplace(current, uint64(index&7), batch)
		}
	}
	runtime.ReadMemStats(&after)
	sink = current
	allocations := after.Mallocs - before.Mallocs
	fmt.Printf("ALLOC impl=go operation=%s batch=%d steps=%d allocs_per_step=%.6f allocs_per_event=%.6f\n",
		operation,
		batch,
		iterations,
		float64(allocations)/float64(iterations),
		float64(allocations)/(float64(iterations)*float64(batch)))
}

func printTiming(operation string, iterations, repetition int, batch uint64, elapsed time.Duration) {
	events := float64(iterations)
	if batch != 0 {
		events *= float64(batch)
	}
	fmt.Printf("BENCH impl=go operation=%s batch=%d rep=%d steps=%d ns_per_step=%.3f ns_per_event=%.3f\n",
		operation,
		batch,
		repetition,
		iterations,
		float64(elapsed.Nanoseconds())/float64(iterations),
		float64(elapsed.Nanoseconds())/events)
}

func timeRoundtrip(iterations, repetition int) {
	current := newState(241 + uint64(repetition))
	for index := 0; index < 10000; index++ {
		current = roundtrip(current)
	}
	runtime.GC()
	started := time.Now()
	for index := 0; index < iterations; index++ {
		current = roundtrip(current)
	}
	elapsed := time.Since(started)
	sink = current
	printTiming("roundtrip", iterations, repetition, 0, elapsed)
}

func timeUnique(iterations, repetition int, batch uint64) {
	current := newState(241 + uint64(repetition))
	for index := 0; index < 10000; index++ {
		current = stepUnique(current, uint64(index&7), batch)
	}
	runtime.GC()
	started := time.Now()
	for index := 0; index < iterations; index++ {
		current = stepUnique(current, uint64(index&7), batch)
	}
	elapsed := time.Since(started)
	sink = current
	printTiming("unique", iterations, repetition, batch, elapsed)
}

func timeReplace(iterations, repetition int, batch uint64) {
	current := newState(241 + uint64(repetition))
	for index := 0; index < 10000; index++ {
		current = stepReplace(current, uint64(index&7), batch)
	}
	runtime.GC()
	started := time.Now()
	for index := 0; index < iterations; index++ {
		current = stepReplace(current, uint64(index&7), batch)
	}
	elapsed := time.Since(started)
	sink = current
	printTiming("replace", iterations, repetition, batch, elapsed)
}

func main() {
	runtime.GOMAXPROCS(1)
	iterations := positiveEnv("EXPLICIT_STATE_ITERS", 1000000, 1000)
	repetitions := positiveEnv("EXPLICIT_STATE_REPS", 9, 3)
	countIterations := iterations
	if countIterations > 100000 {
		countIterations = 100000
	}

	fmt.Printf("ENV impl=go state_bytes=%d gomaxprocs=%d\n", unsafe.Sizeof(state{}), runtime.GOMAXPROCS(0))
	allocationCountRoundtrip(countIterations)
	for _, batch := range []uint64{1, 4, 16} {
		allocationCountTransition("unique", countIterations, batch)
		allocationCountTransition("replace", countIterations, batch)
	}
	for repetition := 0; repetition < repetitions; repetition++ {
		timeRoundtrip(iterations, repetition)
		for _, batch := range []uint64{1, 4, 16} {
			timeUnique(iterations, repetition, batch)
			timeReplace(iterations, repetition, batch)
		}
	}

	fmt.Printf("SINK checksum=%d steps=%d\n", sink.checksum, sink.steps)
}
