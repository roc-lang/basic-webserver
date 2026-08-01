package main

import (
	"fmt"
	"os"
	"runtime"
	"strconv"
	"time"
)

// FunctionalMachine is the closest Go spelling of the Roc spike: each call
// returns an immutable continuation that captures the next state.
type FunctionalMachine func(uint64) FunctionalMachine

// ReusedMachine is the idiomatic unique-owner Go target. It keeps the same
// indirect function-value dispatch as the Roc erased callable while updating
// storage in place.
type ReusedMachine struct {
	value uint64
	step  func(*ReusedMachine, uint64) *ReusedMachine
}

var functionalSink FunctionalMachine
var reusedSink *ReusedMachine
var valueSink uint64

//go:noinline
func functionalFromValue(value uint64) FunctionalMachine {
	return func(wake uint64) FunctionalMachine {
		return functionalFromValue(value + wake + 1)
	}
}

//go:noinline
func reusedStep(machine *ReusedMachine, wake uint64) *ReusedMachine {
	machine.value += wake + 1
	return machine
}

func newReusedMachine(value uint64) *ReusedMachine {
	return &ReusedMachine{value: value, step: reusedStep}
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

func allocationCount(iterations int) {
	functional := functionalFromValue(0)
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	for index := 0; index < iterations; index++ {
		functional = functional(uint64(index & 7))
	}
	runtime.ReadMemStats(&after)
	functionalSink = functional
	fmt.Printf("ALLOC impl=go machine=functional steps=%d allocs_per_op=%.6f\n",
		iterations, float64(after.Mallocs-before.Mallocs)/float64(iterations))

	reused := newReusedMachine(0)
	runtime.GC()
	runtime.ReadMemStats(&before)
	for index := 0; index < iterations; index++ {
		reused = reused.step(reused, uint64(index&7))
	}
	runtime.ReadMemStats(&after)
	reusedSink = reused
	fmt.Printf("ALLOC impl=go machine=reused steps=%d allocs_per_op=%.6f\n",
		iterations, float64(after.Mallocs-before.Mallocs)/float64(iterations))
}

func timeFunctional(iterations, repetition int) {
	machine := functionalFromValue(uint64(repetition))
	for index := 0; index < 10_000; index++ {
		machine = machine(uint64(index & 7))
	}
	runtime.GC()
	started := time.Now()
	for index := 0; index < iterations; index++ {
		machine = machine(uint64(index & 7))
	}
	elapsed := time.Since(started)
	functionalSink = machine
	fmt.Printf("BENCH impl=go machine=functional rep=%d iterations=%d ns_per_op=%.3f\n",
		repetition, iterations, float64(elapsed.Nanoseconds())/float64(iterations))
}

func timeReused(iterations, repetition int) {
	machine := newReusedMachine(uint64(repetition))
	for index := 0; index < 10_000; index++ {
		machine = machine.step(machine, uint64(index&7))
	}
	runtime.GC()
	started := time.Now()
	for index := 0; index < iterations; index++ {
		machine = machine.step(machine, uint64(index&7))
	}
	elapsed := time.Since(started)
	reusedSink = machine
	valueSink = machine.value
	fmt.Printf("BENCH impl=go machine=reused rep=%d iterations=%d ns_per_op=%.3f\n",
		repetition, iterations, float64(elapsed.Nanoseconds())/float64(iterations))
}

func main() {
	runtime.GOMAXPROCS(1)
	iterations := positiveEnv("ABI_SPIKE_ITERS", 1_000_000, 1_000)
	countIterations := iterations
	if countIterations > 100_000 {
		countIterations = 100_000
	}
	allocationCount(countIterations)
	for repetition := 0; repetition < 7; repetition++ {
		timeFunctional(iterations, repetition)
		timeReused(iterations, repetition)
	}
	fmt.Printf("SINK value=%d\n", valueSink)
}
