#define _POSIX_C_SOURCE 200809L

#include "roc_platform_abi.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static _Atomic uint64_t allocation_calls;
static _Atomic uint64_t deallocation_calls;
static _Atomic uint64_t reallocation_calls;
static _Atomic int64_t live_allocations;
static bool track_allocations = true;
static bool benchmark_pool_mode;
static void *benchmark_cached_state_allocation;

#define BENCHMARK_STATE_ALLOCATION_BYTES 96

static _Atomic uint64_t resource_allocations;
static _Atomic uint64_t resource_deallocations;
static _Atomic uint64_t active_observers;
static _Atomic uint64_t max_active_observers;
static _Atomic uint64_t observed_calls;
static _Atomic uint64_t observed_sum;

static pthread_mutex_t observe_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t observe_condition = PTHREAD_COND_INITIALIZER;
static bool block_observe;
static bool release_observe;
static uint64_t entered_observe;

#define MAX_TRACKED_RESOURCES 64
struct ResourceEntry {
    void *base;
    bool live;
};

static pthread_mutex_t resource_mutex = PTHREAD_MUTEX_INITIALIZER;
static struct ResourceEntry resources[MAX_TRACKED_RESOURCES];

static void fail(const char *message) {
    fprintf(stderr, "EXPLICIT STATE SPIKE FAILED: %s\n", message);
    abort();
}

static void check(bool condition, const char *message) {
    if (!condition) {
        fail(message);
    }
}

static size_t normalized_alignment(size_t alignment) {
    size_t result = alignment < sizeof(void *) ? sizeof(void *) : alignment;
    check((result & (result - 1)) == 0, "non-power-of-two allocation alignment");
    return result;
}

void *roc_alloc(size_t length, size_t alignment) {
    if (benchmark_pool_mode) {
        check(length == BENCHMARK_STATE_ALLOCATION_BYTES,
              "pooled benchmark made an unexpected allocation");
        check(alignment <= 8, "pooled benchmark requested unexpected alignment");
        if (benchmark_cached_state_allocation != NULL) {
            void *pointer = benchmark_cached_state_allocation;
            benchmark_cached_state_allocation = NULL;
            return pointer;
        }
    }
    void *pointer = NULL;
    const size_t actual_length = length == 0 ? 1 : length;
    if (posix_memalign(&pointer, normalized_alignment(alignment), actual_length) != 0 ||
        pointer == NULL) {
        fail("roc_alloc failed");
    }
    if (track_allocations) {
        atomic_fetch_add_explicit(&allocation_calls, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&live_allocations, 1, memory_order_relaxed);
    }
    return pointer;
}

static bool mark_resource_deallocated(void *base) {
    bool found = false;
    pthread_mutex_lock(&resource_mutex);
    for (size_t index = 0; index < MAX_TRACKED_RESOURCES; index += 1) {
        if (resources[index].base == base && resources[index].live) {
            resources[index].live = false;
            found = true;
            break;
        }
    }
    pthread_mutex_unlock(&resource_mutex);
    return found;
}

void roc_dealloc(void *pointer, size_t alignment) {
    (void)alignment;
    if (pointer == NULL) {
        return;
    }
    if (benchmark_pool_mode) {
        check(benchmark_cached_state_allocation == NULL,
              "pooled benchmark freed more than one allocation per step");
        benchmark_cached_state_allocation = pointer;
        return;
    }
    if (track_allocations) {
        if (mark_resource_deallocated(pointer)) {
            atomic_fetch_add_explicit(&resource_deallocations, 1, memory_order_relaxed);
        }
        atomic_fetch_add_explicit(&deallocation_calls, 1, memory_order_relaxed);
        atomic_fetch_sub_explicit(&live_allocations, 1, memory_order_relaxed);
    }
    free(pointer);
}

void *roc_realloc(void *pointer, size_t new_length, size_t alignment) {
    check(alignment <= _Alignof(max_align_t), "cannot preserve over-aligned realloc");
    void *result = realloc(pointer, new_length == 0 ? 1 : new_length);
    check(result != NULL, "roc_realloc failed");
    if (track_allocations) {
        atomic_fetch_add_explicit(&reallocation_calls, 1, memory_order_relaxed);
    }
    return result;
}

void roc_dbg(const uint8_t *bytes, size_t length) {
    fwrite(bytes, 1, length, stderr);
    fputc('\n', stderr);
}

void roc_expect_failed(const uint8_t *bytes, size_t length) {
    fwrite(bytes, 1, length, stderr);
    fputc('\n', stderr);
    abort();
}

void roc_crashed(const uint8_t *bytes, size_t length) {
    fwrite(bytes, 1, length, stderr);
    fputc('\n', stderr);
    abort();
}

static void register_resource(void *base) {
    pthread_mutex_lock(&resource_mutex);
    for (size_t index = 0; index < MAX_TRACKED_RESOURCES; index += 1) {
        if (!resources[index].live) {
            resources[index].base = base;
            resources[index].live = true;
            pthread_mutex_unlock(&resource_mutex);
            atomic_fetch_add_explicit(&resource_allocations, 1, memory_order_relaxed);
            return;
        }
    }
    pthread_mutex_unlock(&resource_mutex);
    fail("resource tracker capacity exhausted");
}

uint64_t *hosted_explicit_make_resource(uint64_t value) {
    const size_t header_size = sizeof(intptr_t);
    uint8_t *base = roc_alloc(header_size + sizeof(uint64_t), _Alignof(uint64_t));
    _Atomic intptr_t *refcount = (_Atomic intptr_t *)base;
    atomic_store_explicit(refcount, 1, memory_order_relaxed);
    uint64_t *payload = (uint64_t *)(base + header_size);
    *payload = value;
    register_resource(base);
    return payload;
}

static void resource_decref(uint64_t *payload) {
    check(payload != NULL, "resource payload was null");
    _Atomic intptr_t *refcount = (_Atomic intptr_t *)((uint8_t *)payload - sizeof(intptr_t));
    const intptr_t previous = atomic_fetch_sub_explicit(refcount, 1, memory_order_release);
    check(previous > 0, "resource refcount underflow");
    if (previous == 1) {
        atomic_thread_fence(memory_order_acquire);
        roc_dealloc(refcount, _Alignof(uint64_t));
    }
}

uint64_t hosted_explicit_touch_resource(uint64_t *payload) {
    check(payload != NULL, "touch received a null resource");
    const uint64_t value = *payload;
    resource_decref(payload);
    return value;
}

static void update_max_active(uint64_t active) {
    uint64_t current = atomic_load_explicit(&max_active_observers, memory_order_relaxed);
    while (active > current &&
           !atomic_compare_exchange_weak_explicit(
               &max_active_observers,
               &current,
               active,
               memory_order_relaxed,
               memory_order_relaxed)) {
    }
}

void hosted_explicit_observe(uint64_t value) {
    const uint64_t active =
        atomic_fetch_add_explicit(&active_observers, 1, memory_order_relaxed) + 1;
    update_max_active(active);

    pthread_mutex_lock(&observe_mutex);
    entered_observe += 1;
    pthread_cond_broadcast(&observe_condition);
    while (block_observe && !release_observe) {
        pthread_cond_wait(&observe_condition, &observe_mutex);
    }
    pthread_mutex_unlock(&observe_mutex);

    atomic_fetch_add_explicit(&observed_calls, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&observed_sum, value, memory_order_relaxed);
    atomic_fetch_sub_explicit(&active_observers, 1, memory_order_relaxed);
}

static void configure_observe_block(bool block) {
    pthread_mutex_lock(&observe_mutex);
    block_observe = block;
    release_observe = !block;
    entered_observe = 0;
    pthread_mutex_unlock(&observe_mutex);
}

static void wait_for_observe_entries(uint64_t target) {
    pthread_mutex_lock(&observe_mutex);
    while (entered_observe < target) {
        pthread_cond_wait(&observe_condition, &observe_mutex);
    }
    pthread_mutex_unlock(&observe_mutex);
}

static void release_observers(void) {
    pthread_mutex_lock(&observe_mutex);
    release_observe = true;
    pthread_cond_broadcast(&observe_condition);
    pthread_mutex_unlock(&observe_mutex);
}

static void assert_balanced(const char *scenario) {
    const int64_t live = atomic_load_explicit(&live_allocations, memory_order_relaxed);
    const uint64_t made = atomic_load_explicit(&resource_allocations, memory_order_relaxed);
    const uint64_t dropped = atomic_load_explicit(&resource_deallocations, memory_order_relaxed);
    if (live != 0 || made != dropped) {
        fprintf(stderr,
                "%s imbalance: live=%lld resources=%llu/%llu\n",
                scenario,
                (long long)live,
                (unsigned long long)made,
                (unsigned long long)dropped);
        abort();
    }
}

struct StateWorker {
    RocBox state;
    uint64_t wake;
    uint64_t event_count;
    size_t advances;
    bool drop_result;
};

static void *run_state_worker(void *raw_worker) {
    struct StateWorker *worker = raw_worker;
    RocBox state = worker->state;
    for (size_t index = 0; index < worker->advances; index += 1) {
        state = roc_explicit_step_state(
            state, worker->wake + (uint64_t)index, worker->event_count);
    }
    if (worker->drop_result) {
        roc_explicit_drop_state(state);
        state = NULL;
    }
    worker->state = state;
    return NULL;
}

struct StateSlot {
    _Atomic bool busy;
    _Atomic bool cancelled;
    RocBox state;
};

static bool advance_slot(struct StateSlot *slot, uint64_t wake, uint64_t event_count) {
    bool expected = false;
    if (!atomic_compare_exchange_strong_explicit(
            &slot->busy,
            &expected,
            true,
            memory_order_acquire,
            memory_order_relaxed)) {
        return false;
    }

    RocBox input = slot->state;
    slot->state = NULL;
    check(input != NULL, "acquired slot without owned state");
    RocBox next = roc_explicit_step_state(input, wake, event_count);
    if (atomic_load_explicit(&slot->cancelled, memory_order_acquire)) {
        roc_explicit_drop_state(next);
    } else {
        slot->state = next;
    }
    atomic_store_explicit(&slot->busy, false, memory_order_release);
    return true;
}

struct SlotWorker {
    struct StateSlot *slot;
    uint64_t wake;
    bool advanced;
};

static void *run_slot_worker(void *raw_worker) {
    struct SlotWorker *worker = raw_worker;
    worker->advanced = advance_slot(worker->slot, worker->wake, 1);
    return NULL;
}

static void test_parked_and_returned_drop(void) {
    roc_explicit_drop_state(roc_explicit_init_state(2));
    assert_balanced("parked drop");

    RocBox returned = roc_explicit_step_state(roc_explicit_init_state(3), 7, 4);
    roc_explicit_drop_state(returned);
    assert_balanced("returned-state drop");

    RocBox packaged = roc_explicit_init_packaged_state(5);
    packaged = roc_explicit_step_state(packaged, 11, 4);
    roc_explicit_drop_state(packaged);
    assert_balanced("package-opaque route state");
}

static void test_sequential_thread_migration(void) {
    RocBox state = roc_explicit_init_state(4);
    for (uint64_t thread_index = 0; thread_index < 4; thread_index += 1) {
        struct StateWorker worker = {
            .state = state,
            .wake = thread_index * 10,
            .event_count = 4,
            .advances = 3,
            .drop_result = false,
        };
        pthread_t thread;
        check(pthread_create(&thread, NULL, run_state_worker, &worker) == 0,
              "failed to create migration worker");
        check(pthread_join(thread, NULL) == 0, "failed to join migration worker");
        state = worker.state;
    }
    roc_explicit_drop_state(state);
    assert_balanced("sequential thread migration");
}

static void test_independent_concurrency(void) {
    atomic_store_explicit(&max_active_observers, 0, memory_order_relaxed);
    configure_observe_block(true);
    struct StateWorker left = {
        .state = roc_explicit_init_state(6),
        .wake = 1,
        .event_count = 1,
        .advances = 1,
        .drop_result = true,
    };
    struct StateWorker right = {
        .state = roc_explicit_init_state(7),
        .wake = 2,
        .event_count = 1,
        .advances = 1,
        .drop_result = true,
    };
    pthread_t left_thread;
    pthread_t right_thread;
    check(pthread_create(&left_thread, NULL, run_state_worker, &left) == 0,
          "failed to create left concurrency worker");
    check(pthread_create(&right_thread, NULL, run_state_worker, &right) == 0,
          "failed to create right concurrency worker");
    wait_for_observe_entries(2);
    release_observers();
    check(pthread_join(left_thread, NULL) == 0, "failed to join left concurrency worker");
    check(pthread_join(right_thread, NULL) == 0, "failed to join right concurrency worker");
    configure_observe_block(false);
    check(atomic_load_explicit(&max_active_observers, memory_order_relaxed) >= 2,
          "independent states did not execute concurrently");
    assert_balanced("independent concurrency");
}

static void test_overlap_rejection(void) {
    configure_observe_block(true);
    struct StateSlot slot = {
        .busy = false,
        .cancelled = false,
        .state = roc_explicit_init_state(8),
    };
    struct SlotWorker first = {.slot = &slot, .wake = 1, .advanced = false};
    pthread_t thread;
    check(pthread_create(&thread, NULL, run_slot_worker, &first) == 0,
          "failed to create overlap worker");
    wait_for_observe_entries(1);
    check(!advance_slot(&slot, 2, 1), "same-stream overlapping step was accepted");
    release_observers();
    check(pthread_join(thread, NULL) == 0, "failed to join overlap worker");
    check(first.advanced, "first overlap step did not run");
    roc_explicit_drop_state(slot.state);
    configure_observe_block(false);
    assert_balanced("same-stream overlap rejection");
}

static void test_cancel_during_advance(void) {
    configure_observe_block(true);
    struct StateSlot slot = {
        .busy = false,
        .cancelled = false,
        .state = roc_explicit_init_state(9),
    };
    struct SlotWorker worker = {.slot = &slot, .wake = 9, .advanced = false};
    pthread_t thread;
    check(pthread_create(&thread, NULL, run_slot_worker, &worker) == 0,
          "failed to create cancellation worker");
    wait_for_observe_entries(1);
    atomic_store_explicit(&slot.cancelled, true, memory_order_release);
    release_observers();
    check(pthread_join(thread, NULL) == 0, "failed to join cancellation worker");
    check(worker.advanced, "in-flight cancellation step did not finish");
    check(slot.state == NULL, "cancelled returned state remained parked");
    configure_observe_block(false);
    assert_balanced("in-flight cancellation");
}

static uint64_t monotonic_nanoseconds(void) {
    struct timespec value;
    check(clock_gettime(CLOCK_MONOTONIC, &value) == 0, "clock_gettime failed");
    return (uint64_t)value.tv_sec * 1000000000ULL + (uint64_t)value.tv_nsec;
}

static size_t benchmark_iterations(void) {
    const char *raw = getenv("EXPLICIT_STATE_ITERS");
    if (raw == NULL || *raw == '\0') {
        return 1000000;
    }
    char *end = NULL;
    const unsigned long long parsed = strtoull(raw, &end, 10);
    check(end != raw && *end == '\0' && parsed >= 1000, "invalid EXPLICIT_STATE_ITERS");
    return (size_t)parsed;
}

static size_t benchmark_repetitions(void) {
    const char *raw = getenv("EXPLICIT_STATE_REPS");
    if (raw == NULL || *raw == '\0') {
        return 9;
    }
    char *end = NULL;
    const unsigned long long parsed = strtoull(raw, &end, 10);
    check(end != raw && *end == '\0' && parsed >= 3, "invalid EXPLICIT_STATE_REPS");
    return (size_t)parsed;
}

static void count_transition_allocations(size_t iterations, uint64_t batch) {
    RocBox state = roc_explicit_init_bench_state(100 + batch);
    const uint64_t before_alloc = atomic_load_explicit(&allocation_calls, memory_order_relaxed);
    const uint64_t before_free = atomic_load_explicit(&deallocation_calls, memory_order_relaxed);
    for (size_t index = 0; index < iterations; index += 1) {
        state = roc_explicit_bench_state(state, (uint64_t)(index & 7), batch);
    }
    const uint64_t allocations =
        atomic_load_explicit(&allocation_calls, memory_order_relaxed) - before_alloc;
    const uint64_t deallocations =
        atomic_load_explicit(&deallocation_calls, memory_order_relaxed) - before_free;
    roc_explicit_drop_state(state);
    assert_balanced("counted transition benchmark");
    printf("ALLOC impl=roc operation=transition batch=%llu steps=%zu allocs_per_step=%.6f frees_per_step=%.6f allocs_per_event=%.6f\n",
           (unsigned long long)batch,
           iterations,
           (double)allocations / (double)iterations,
           (double)deallocations / (double)iterations,
           (double)allocations / ((double)iterations * (double)batch));
}

static void count_roundtrip_allocations(size_t iterations) {
    RocBox state = roc_explicit_init_bench_state(100);
    const uint64_t before_alloc = atomic_load_explicit(&allocation_calls, memory_order_relaxed);
    const uint64_t before_free = atomic_load_explicit(&deallocation_calls, memory_order_relaxed);
    for (size_t index = 0; index < iterations; index += 1) {
        state = roc_explicit_roundtrip_state(state);
    }
    const uint64_t allocations =
        atomic_load_explicit(&allocation_calls, memory_order_relaxed) - before_alloc;
    const uint64_t deallocations =
        atomic_load_explicit(&deallocation_calls, memory_order_relaxed) - before_free;
    roc_explicit_drop_state(state);
    assert_balanced("counted roundtrip benchmark");
    printf("ALLOC impl=roc operation=roundtrip batch=0 steps=%zu allocs_per_step=%.6f frees_per_step=%.6f\n",
           iterations,
           (double)allocations / (double)iterations,
           (double)deallocations / (double)iterations);
}

static void time_operation(
    const char *operation,
    size_t iterations,
    size_t repetition,
    uint64_t batch,
    bool use_pool) {
    track_allocations = false;
    RocBox state = roc_explicit_init_bench_state(200 + (uint64_t)repetition);
    benchmark_pool_mode = use_pool;
    const size_t warmup_steps = iterations < 10000 ? iterations : 10000;
    if (batch == 0) {
        for (size_t index = 0; index < warmup_steps; index += 1) {
            state = roc_explicit_roundtrip_state(state);
        }
    } else {
        for (size_t index = 0; index < warmup_steps; index += 1) {
            state = roc_explicit_bench_state(state, (uint64_t)(index & 7), batch);
        }
    }
    const uint64_t started = monotonic_nanoseconds();
    if (batch == 0) {
        for (size_t index = 0; index < iterations; index += 1) {
            state = roc_explicit_roundtrip_state(state);
        }
    } else {
        for (size_t index = 0; index < iterations; index += 1) {
            state = roc_explicit_bench_state(state, (uint64_t)(index & 7), batch);
        }
    }
    const uint64_t elapsed = monotonic_nanoseconds() - started;
    benchmark_pool_mode = false;
    roc_explicit_drop_state(state);
    free(benchmark_cached_state_allocation);
    benchmark_cached_state_allocation = NULL;
    track_allocations = true;
    const double events = batch == 0 ? (double)iterations : (double)iterations * (double)batch;
    printf("BENCH impl=roc operation=%s batch=%llu rep=%zu steps=%zu ns_per_step=%.3f ns_per_event=%.3f\n",
           operation,
           (unsigned long long)batch,
           repetition,
           iterations,
           (double)elapsed / (double)iterations,
           (double)elapsed / events);
}

int main(void) {
    puts("RUN parked_and_returned_drop");
    test_parked_and_returned_drop();
    puts("RUN sequential_thread_migration");
    test_sequential_thread_migration();
    puts("RUN independent_concurrency");
    test_independent_concurrency();
    puts("RUN overlap_rejection");
    test_overlap_rejection();
    puts("RUN cancel_during_advance");
    test_cancel_during_advance();
    check(atomic_load_explicit(&active_observers, memory_order_relaxed) == 0,
          "observer remained active");
    printf("CORRECTNESS ok observed_calls=%llu resource_allocations=%llu resource_deallocations=%llu max_independent=%llu\n",
           (unsigned long long)atomic_load_explicit(&observed_calls, memory_order_relaxed),
           (unsigned long long)atomic_load_explicit(&resource_allocations, memory_order_relaxed),
           (unsigned long long)atomic_load_explicit(&resource_deallocations, memory_order_relaxed),
           (unsigned long long)atomic_load_explicit(&max_active_observers, memory_order_relaxed));

    const size_t iterations = benchmark_iterations();
    const size_t repetitions = benchmark_repetitions();
    const size_t count_iterations = iterations < 100000 ? iterations : 100000;
    count_roundtrip_allocations(count_iterations);
    count_transition_allocations(count_iterations, 1);
    count_transition_allocations(count_iterations, 4);
    count_transition_allocations(count_iterations, 16);
    for (size_t repetition = 0; repetition < repetitions; repetition += 1) {
        time_operation("roundtrip", iterations, repetition, 0, false);
        time_operation("transition", iterations, repetition, 1, false);
        time_operation("transition_pool", iterations, repetition, 1, true);
        time_operation("transition", iterations, repetition, 4, false);
        time_operation("transition_pool", iterations, repetition, 4, true);
        time_operation("transition", iterations, repetition, 16, false);
        time_operation("transition_pool", iterations, repetition, 16, true);
    }

    assert_balanced("final accounting");
    printf("ACCOUNTING allocations=%llu deallocations=%llu reallocations=%llu live=%lld\n",
           (unsigned long long)atomic_load_explicit(&allocation_calls, memory_order_relaxed),
           (unsigned long long)atomic_load_explicit(&deallocation_calls, memory_order_relaxed),
           (unsigned long long)atomic_load_explicit(&reallocation_calls, memory_order_relaxed),
           (long long)atomic_load_explicit(&live_allocations, memory_order_relaxed));
    return 0;
}
