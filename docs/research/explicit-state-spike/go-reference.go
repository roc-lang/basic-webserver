package main

import (
	"fmt"
	"os"
	"runtime"
	"runtime/debug"
	"strconv"
	"time"
)

type state struct {
	checksum uint64
	steps    uint64
}

var sink *state

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
	next := &state{checksum: current.checksum, steps: current.steps}
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

func allocationCount(operation string, iterations int, batch uint64) {
	current := &state{checksum: 141}
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	for index := 0; index < iterations; index++ {
		switch operation {
		case "roundtrip":
			current = roundtrip(current)
		case "unique":
			current = stepUnique(current, uint64(index&7), batch)
		case "replace":
			current = stepReplace(current, uint64(index&7), batch)
		default:
			panic("unknown operation")
		}
	}
	runtime.ReadMemStats(&after)
	sink = current
	allocations := after.Mallocs - before.Mallocs
	if batch == 0 {
		fmt.Printf("ALLOC impl=go operation=%s batch=0 steps=%d allocs_per_step=%.6f\n",
			operation, iterations, float64(allocations)/float64(iterations))
		return
	}
	fmt.Printf("ALLOC impl=go operation=%s batch=%d steps=%d allocs_per_step=%.6f allocs_per_event=%.6f\n",
		operation,
		batch,
		iterations,
		float64(allocations)/float64(iterations),
		float64(allocations)/(float64(iterations)*float64(batch)))
}

func timeOperation(operation string, iterations, repetition int, batch uint64) {
	current := &state{checksum: 241 + uint64(repetition)}
	started := time.Now()
	for index := 0; index < iterations; index++ {
		switch operation {
		case "roundtrip":
			current = roundtrip(current)
		case "unique":
			current = stepUnique(current, uint64(index&7), batch)
		case "replace":
			current = stepReplace(current, uint64(index&7), batch)
		default:
			panic("unknown operation")
		}
	}
	elapsed := time.Since(started)
	sink = current
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

func main() {
	runtime.GOMAXPROCS(1)
	debug.SetGCPercent(-1)
	iterations := positiveEnv("EXPLICIT_STATE_ITERS", 1000000, 1000)
	repetitions := positiveEnv("EXPLICIT_STATE_REPS", 9, 3)
	countIterations := iterations
	if countIterations > 100000 {
		countIterations = 100000
	}

	allocationCount("roundtrip", countIterations, 0)
	for _, batch := range []uint64{1, 4, 16} {
		allocationCount("unique", countIterations, batch)
		allocationCount("replace", countIterations, batch)
	}
	for repetition := 0; repetition < repetitions; repetition++ {
		timeOperation("roundtrip", iterations, repetition, 0)
		for _, batch := range []uint64{1, 4, 16} {
			timeOperation("unique", iterations, repetition, batch)
			timeOperation("replace", iterations, repetition, batch)
		}
	}

	fmt.Printf("SINK checksum=%d steps=%d\n", sink.checksum, sink.steps)
}
