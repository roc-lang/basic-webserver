#define _POSIX_C_SOURCE 200809L

#include "roc_platform_abi.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static _Atomic uint64_t allocation_calls;
static _Atomic uint64_t deallocation_calls;
static _Atomic uint64_t reallocation_calls;
static _Atomic int64_t live_allocations;

static _Atomic uint64_t resource_allocations;
static _Atomic uint64_t resource_deallocations;

static _Atomic uint64_t observed_calls;
static _Atomic uint64_t observed_sum;
static _Atomic uint64_t active_observers;
static _Atomic uint64_t max_active_observers;

#ifdef ABI_SPIKE_DIRECT_ERASED_CALLABLE
extern void roc_builtins_erased_callable_decref(
    RocErasedCallable callable,
    struct RocOps *ops);
#endif

static pthread_mutex_t observe_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t observe_condition = PTHREAD_COND_INITIALIZER;
static bool block_observe;
static bool release_observe;
static bool delay_observe;
static uint64_t entered_observe;

#define MAX_TRACKED_RESOURCES 256
struct ResourceEntry {
    void *base;
    bool live;
};

static pthread_mutex_t resource_mutex = PTHREAD_MUTEX_INITIALIZER;
static struct ResourceEntry resources[MAX_TRACKED_RESOURCES];

static void fail(const char *message) {
    fprintf(stderr, "ABI SPIKE FAILED: %s\n", message);
    abort();
}

static void check(bool condition, const char *message) {
    if (!condition) {
        fail(message);
    }
}

static size_t normalized_alignment(size_t alignment) {
    size_t result = alignment < sizeof(void *) ? sizeof(void *) : alignment;
    if ((result & (result - 1)) != 0) {
        fail("Roc requested non-power-of-two allocation alignment");
    }
    return result;
}

void *roc_alloc(size_t length, size_t alignment) {
    void *pointer = NULL;
    const size_t actual_alignment = normalized_alignment(alignment);
    const size_t actual_length = length == 0 ? 1 : length;
    if (posix_memalign(&pointer, actual_alignment, actual_length) != 0 || pointer == NULL) {
        fail("roc_alloc failed");
    }
    atomic_fetch_add_explicit(&allocation_calls, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&live_allocations, 1, memory_order_relaxed);
    return pointer;
}

static bool mark_resource_deallocated(void *base) {
    bool found = false;
    pthread_mutex_lock(&resource_mutex);
    for (size_t index = 0; index < MAX_TRACKED_RESOURCES; index += 1) {
        if (resources[index].base == base) {
            if (resources[index].live) {
                resources[index].live = false;
                found = true;
                break;
            }
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
    if (mark_resource_deallocated(pointer)) {
        atomic_fetch_add_explicit(&resource_deallocations, 1, memory_order_relaxed);
    }
    atomic_fetch_add_explicit(&deallocation_calls, 1, memory_order_relaxed);
    atomic_fetch_sub_explicit(&live_allocations, 1, memory_order_relaxed);
    free(pointer);
}

void *roc_realloc(void *pointer, size_t new_length, size_t alignment) {
    if (alignment > _Alignof(max_align_t)) {
        fail("spike host cannot preserve an over-aligned realloc");
    }
    void *result = realloc(pointer, new_length == 0 ? 1 : new_length);
    if (result == NULL) {
        fail("roc_realloc failed");
    }
    atomic_fetch_add_explicit(&reallocation_calls, 1, memory_order_relaxed);
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
    fail("opaque resource tracker capacity exhausted");
}

uint64_t *hosted_abi_make_resource(uint64_t value) {
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
    check(payload != NULL, "hosted resource argument was null");
    _Atomic intptr_t *refcount = (_Atomic intptr_t *)((uint8_t *)payload - sizeof(intptr_t));
    const intptr_t previous = atomic_fetch_sub_explicit(refcount, 1, memory_order_release);
    check(previous > 0, "opaque resource refcount underflow");
    if (previous == 1) {
        atomic_thread_fence(memory_order_acquire);
        roc_dealloc(refcount, _Alignof(uint64_t));
    }
}

uint64_t hosted_abi_touch_resource(uint64_t *payload) {
    check(payload != NULL, "hosted touch received null resource");
    const uint64_t result = *payload;
    resource_decref(payload);
    return result;
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

void hosted_abi_observe(uint64_t value) {
    const uint64_t active =
        atomic_fetch_add_explicit(&active_observers, 1, memory_order_relaxed) + 1;
    update_max_active(active);

    pthread_mutex_lock(&observe_mutex);
    entered_observe += 1;
    pthread_cond_broadcast(&observe_condition);
    while (block_observe && !release_observe) {
        pthread_cond_wait(&observe_condition, &observe_mutex);
    }
    const bool should_delay = delay_observe;
    pthread_mutex_unlock(&observe_mutex);

    if (should_delay) {
        const struct timespec pause = {.tv_sec = 0, .tv_nsec = 1000000};
        nanosleep(&pause, NULL);
    }

    atomic_fetch_add_explicit(&observed_calls, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&observed_sum, value, memory_order_relaxed);
    atomic_fetch_sub_explicit(&active_observers, 1, memory_order_relaxed);
}

struct MachineWorker {
    RocErasedCallable machine;
    uint64_t wake;
    size_t advances;
    bool drop_result;
};

struct U64Args {
    uint64_t arg0;
};

static void direct_drop_machine(RocErasedCallable machine) {
#ifdef ABI_SPIKE_DIRECT_ERASED_CALLABLE
    check(machine != NULL, "attempted to drop a null erased callable");
    roc_builtins_erased_callable_decref(machine, NULL);
#else
    (void)machine;
    fail("direct erased-callable diagnostic is unavailable in this build");
#endif
}

static RocErasedCallable direct_advance_machine(RocErasedCallable machine, uint64_t wake) {
#ifdef ABI_SPIKE_DIRECT_ERASED_CALLABLE
    check(machine != NULL, "attempted to advance a null erased callable");
    RocErasedCallablePayload *payload = roc_erased_callable_payload_ptr(machine);
    struct U64Args args = {.arg0 = wake};
    RocErasedCallable next = NULL;
    payload->callable_fn_ptr(
        NULL,
        (uint8_t *)&next,
        (const uint8_t *)&args,
        roc_erased_callable_capture_ptr(machine));
    direct_drop_machine(machine);
    check(next != NULL, "erased machine returned a null continuation");
    return next;
#else
    (void)machine;
    (void)wake;
    fail("direct erased-callable diagnostic is unavailable in this build");
    return NULL;
#endif
}

static void *run_machine_worker(void *raw_worker) {
    struct MachineWorker *worker = raw_worker;
    RocErasedCallable machine = worker->machine;
    for (size_t index = 0; index < worker->advances; index += 1) {
        machine = direct_advance_machine(machine, worker->wake + index);
    }
    if (worker->drop_result) {
        direct_drop_machine(machine);
        machine = NULL;
    }
    worker->machine = machine;
    return NULL;
}

struct MachineSlot {
    _Atomic bool busy;
    _Atomic bool cancelled;
    RocErasedCallable machine;
};

static bool advance_slot(struct MachineSlot *slot, uint64_t wake) {
    bool expected = false;
    if (!atomic_compare_exchange_strong_explicit(
            &slot->busy,
            &expected,
            true,
            memory_order_acquire,
            memory_order_relaxed)) {
        return false;
    }

    RocErasedCallable input = slot->machine;
    slot->machine = NULL;
    check(input != NULL, "slot acquired without an owned machine");
    RocErasedCallable next = direct_advance_machine(input, wake);
    if (atomic_load_explicit(&slot->cancelled, memory_order_acquire)) {
        direct_drop_machine(next);
    } else {
        slot->machine = next;
    }
    atomic_store_explicit(&slot->busy, false, memory_order_release);
    return true;
}

struct SlotWorker {
    struct MachineSlot *slot;
    uint64_t wake;
    bool advanced;
};

static void *run_slot_worker(void *raw_worker) {
    struct SlotWorker *worker = raw_worker;
    worker->advanced = advance_slot(worker->slot, worker->wake);
    return NULL;
}

static void wait_for_observe_entries(uint64_t target) {
    pthread_mutex_lock(&observe_mutex);
    while (entered_observe < target) {
        pthread_cond_wait(&observe_condition, &observe_mutex);
    }
    pthread_mutex_unlock(&observe_mutex);
}

static void configure_observe_block(bool block) {
    pthread_mutex_lock(&observe_mutex);
    block_observe = block;
    release_observe = !block;
    entered_observe = 0;
    pthread_mutex_unlock(&observe_mutex);
}

static void release_observers(void) {
    pthread_mutex_lock(&observe_mutex);
    release_observe = true;
    pthread_cond_broadcast(&observe_condition);
    pthread_mutex_unlock(&observe_mutex);
}

static void assert_no_live_allocations(const char *scenario) {
    const int64_t live = atomic_load_explicit(&live_allocations, memory_order_relaxed);
    if (live != 0) {
        fprintf(stderr, "%s left %lld live allocations\n", scenario, (long long)live);
        abort();
    }
}

static void test_sequential_thread_migration(void) {
    RocErasedCallable machine = roc_abi_make_machine(10);
    for (uint64_t thread_index = 0; thread_index < 4; thread_index += 1) {
        struct MachineWorker worker = {
            .machine = machine,
            .wake = thread_index * 10,
            .advances = 3,
            .drop_result = false,
        };
        pthread_t thread;
        check(pthread_create(&thread, NULL, run_machine_worker, &worker) == 0,
              "failed to create migration worker");
        check(pthread_join(thread, NULL) == 0, "failed to join migration worker");
        machine = worker.machine;
    }
    direct_drop_machine(machine);
    assert_no_live_allocations("sequential migration");
}

static void test_parked_and_returned_drop(void) {
    RocErasedCallable parked = roc_abi_make_machine(20);
    direct_drop_machine(parked);
    assert_no_live_allocations("parked drop");

    RocErasedCallable returned = direct_advance_machine(roc_abi_make_machine(21), 7);
    direct_drop_machine(returned);
    assert_no_live_allocations("returned-value drop");
}

static void test_independent_concurrency(void) {
    atomic_store_explicit(&max_active_observers, 0, memory_order_relaxed);
    pthread_mutex_lock(&observe_mutex);
    delay_observe = true;
    pthread_mutex_unlock(&observe_mutex);

    struct MachineWorker left = {
        .machine = roc_abi_make_machine(30),
        .wake = 1,
        .advances = 20,
        .drop_result = true,
    };
    struct MachineWorker right = {
        .machine = roc_abi_make_machine(40),
        .wake = 2,
        .advances = 20,
        .drop_result = true,
    };
    pthread_t left_thread;
    pthread_t right_thread;
    check(pthread_create(&left_thread, NULL, run_machine_worker, &left) == 0,
          "failed to create left concurrency worker");
    check(pthread_create(&right_thread, NULL, run_machine_worker, &right) == 0,
          "failed to create right concurrency worker");
    check(pthread_join(left_thread, NULL) == 0, "failed to join left concurrency worker");
    check(pthread_join(right_thread, NULL) == 0, "failed to join right concurrency worker");

    pthread_mutex_lock(&observe_mutex);
    delay_observe = false;
    pthread_mutex_unlock(&observe_mutex);
    check(atomic_load_explicit(&max_active_observers, memory_order_relaxed) >= 2,
          "independent Roc machines did not execute concurrently");
    assert_no_live_allocations("independent concurrency");
}

static void test_overlap_rejection(void) {
    configure_observe_block(true);
    struct MachineSlot slot = {
        .busy = false,
        .cancelled = false,
        .machine = roc_abi_make_machine(50),
    };
    struct SlotWorker first = {.slot = &slot, .wake = 1, .advanced = false};
    pthread_t first_thread;
    check(pthread_create(&first_thread, NULL, run_slot_worker, &first) == 0,
          "failed to create overlap worker");
    wait_for_observe_entries(1);
    check(!advance_slot(&slot, 2), "same-machine overlapping advance was accepted");
    release_observers();
    check(pthread_join(first_thread, NULL) == 0, "failed to join overlap worker");
    check(first.advanced, "first slot advance did not run");
    direct_drop_machine(slot.machine);
    configure_observe_block(false);
    assert_no_live_allocations("overlap rejection");
}

static void test_cancel_during_advance(void) {
    configure_observe_block(true);
    struct MachineSlot slot = {
        .busy = false,
        .cancelled = false,
        .machine = roc_abi_make_machine(60),
    };
    struct SlotWorker worker = {.slot = &slot, .wake = 9, .advanced = false};
    pthread_t thread;
    check(pthread_create(&thread, NULL, run_slot_worker, &worker) == 0,
          "failed to create cancellation worker");
    wait_for_observe_entries(1);
    atomic_store_explicit(&slot.cancelled, true, memory_order_release);
    release_observers();
    check(pthread_join(thread, NULL) == 0, "failed to join cancellation worker");
    check(worker.advanced, "in-flight cancellation worker did not advance");
    check(slot.machine == NULL, "cancelled in-flight result remained parked");
    configure_observe_block(false);
    assert_no_live_allocations("in-flight cancellation");
}

static uint64_t monotonic_nanoseconds(void) {
    struct timespec value;
    check(clock_gettime(CLOCK_MONOTONIC, &value) == 0, "clock_gettime failed");
    return (uint64_t)value.tv_sec * 1000000000ULL + (uint64_t)value.tv_nsec;
}

static size_t benchmark_iterations(void) {
    const char *raw = getenv("ABI_SPIKE_ITERS");
    if (raw == NULL || *raw == '\0') {
        return 1000000;
    }
    char *end = NULL;
    const unsigned long long parsed = strtoull(raw, &end, 10);
    check(end != raw && *end == '\0' && parsed >= 1000, "invalid ABI_SPIKE_ITERS");
    return (size_t)parsed;
}

static void benchmark_machine(size_t iterations, size_t repetition) {
    RocErasedCallable machine = roc_abi_make_bench_machine((uint64_t)repetition);
    const uint64_t allocations_before =
        atomic_load_explicit(&allocation_calls, memory_order_relaxed);
    const uint64_t deallocations_before =
        atomic_load_explicit(&deallocation_calls, memory_order_relaxed);
    const uint64_t started = monotonic_nanoseconds();
    for (size_t index = 0; index < iterations; index += 1) {
        machine = direct_advance_machine(machine, (uint64_t)(index & 7));
    }
    const uint64_t elapsed = monotonic_nanoseconds() - started;
    const uint64_t allocations =
        atomic_load_explicit(&allocation_calls, memory_order_relaxed) - allocations_before;
    const uint64_t deallocations =
        atomic_load_explicit(&deallocation_calls, memory_order_relaxed) - deallocations_before;
    direct_drop_machine(machine);
    printf("BENCH machine rep=%zu iterations=%zu ns_per_op=%.3f allocs_per_op=%.6f frees_per_op=%.6f\n",
           repetition,
           iterations,
           (double)elapsed / (double)iterations,
           (double)allocations / (double)iterations,
           (double)deallocations / (double)iterations);
}

static void benchmark_state(size_t iterations, size_t repetition) {
    RocBox state = roc_abi_init_state((uint64_t)(100 + repetition));
    const uint64_t allocations_before =
        atomic_load_explicit(&allocation_calls, memory_order_relaxed);
    const uint64_t deallocations_before =
        atomic_load_explicit(&deallocation_calls, memory_order_relaxed);
    const uint64_t started = monotonic_nanoseconds();
    for (size_t index = 0; index < iterations; index += 1) {
        state = roc_abi_bench_step_state(state, (uint64_t)(index & 7));
    }
    const uint64_t elapsed = monotonic_nanoseconds() - started;
    const uint64_t allocations =
        atomic_load_explicit(&allocation_calls, memory_order_relaxed) - allocations_before;
    const uint64_t deallocations =
        atomic_load_explicit(&deallocation_calls, memory_order_relaxed) - deallocations_before;
    roc_abi_drop_state(state);
    printf("BENCH state rep=%zu iterations=%zu ns_per_op=%.3f allocs_per_op=%.6f frees_per_op=%.6f\n",
           repetition,
           iterations,
           (double)elapsed / (double)iterations,
           (double)allocations / (double)iterations,
           (double)deallocations / (double)iterations);
}

static int run_wrapper_negative(void) {
    puts("RUN plain_box_parked_drop");
    fflush(stdout);
    roc_abi_drop_box(roc_abi_make_box(1));
    assert_no_live_allocations("plain box parked drop");
    puts("RUN platform_nonrecursive_callable_parked_drop");
    fflush(stdout);
    RocErasedCallable platform_callable = roc_abi_make_platform_callable(1);
    printf("POINTER platform_callable=%p\n", (void *)platform_callable);
    fflush(stdout);
    roc_abi_drop_callable(platform_callable);
    fail("generated boxed-callable drop wrapper unexpectedly returned");
    return 1;
}

int main(void) {
    const char *mode = getenv("ABI_SPIKE_MODE");
    if (mode != NULL && strcmp(mode, "wrapper-negative") == 0) {
        return run_wrapper_negative();
    }

    puts("RUN direct_platform_nonrecursive_callable_parked_drop");
    fflush(stdout);
    direct_drop_machine(roc_abi_make_platform_callable(1));
    assert_no_live_allocations("direct platform nonrecursive callable parked drop");
    puts("RUN direct_app_nonrecursive_callable_parked_drop");
    fflush(stdout);
    direct_drop_machine(roc_abi_make_callable(1));
    assert_no_live_allocations("direct app nonrecursive callable parked drop");
    puts("RUN explicit_state_parked_drop");
    fflush(stdout);
    roc_abi_drop_state(roc_abi_init_state(1));
    assert_no_live_allocations("explicit state parked drop");
    puts("RUN direct_pure_recursive_parked_drop");
    fflush(stdout);
    direct_drop_machine(roc_abi_make_bench_machine(1));
    assert_no_live_allocations("direct pure recursive parked drop");

    puts("RUN parked_and_returned_drop");
    fflush(stdout);
    test_parked_and_returned_drop();
    puts("RUN sequential_thread_migration");
    fflush(stdout);
    test_sequential_thread_migration();
    puts("RUN independent_concurrency");
    fflush(stdout);
    test_independent_concurrency();
    puts("RUN overlap_rejection");
    fflush(stdout);
    test_overlap_rejection();
    puts("RUN cancel_during_advance");
    fflush(stdout);
    test_cancel_during_advance();

    check(atomic_load_explicit(&resource_allocations, memory_order_relaxed) ==
              atomic_load_explicit(&resource_deallocations, memory_order_relaxed),
          "opaque resource allocation/deallocation count differed");
    check(atomic_load_explicit(&active_observers, memory_order_relaxed) == 0,
          "observer remained active after lifecycle tests");

    printf("CORRECTNESS ok observed_calls=%llu resource_allocations=%llu resource_deallocations=%llu max_independent=%llu\n",
           (unsigned long long)atomic_load_explicit(&observed_calls, memory_order_relaxed),
           (unsigned long long)atomic_load_explicit(&resource_allocations, memory_order_relaxed),
           (unsigned long long)atomic_load_explicit(&resource_deallocations, memory_order_relaxed),
           (unsigned long long)atomic_load_explicit(&max_active_observers, memory_order_relaxed));

    const size_t iterations = benchmark_iterations();
    for (size_t repetition = 0; repetition < 7; repetition += 1) {
        benchmark_machine(iterations, repetition);
        assert_no_live_allocations("machine benchmark");
        benchmark_state(iterations, repetition);
        assert_no_live_allocations("state benchmark");
    }

    printf("ACCOUNTING allocations=%llu deallocations=%llu reallocations=%llu live=%lld\n",
           (unsigned long long)atomic_load_explicit(&allocation_calls, memory_order_relaxed),
           (unsigned long long)atomic_load_explicit(&deallocation_calls, memory_order_relaxed),
           (unsigned long long)atomic_load_explicit(&reallocation_calls, memory_order_relaxed),
           (long long)atomic_load_explicit(&live_allocations, memory_order_relaxed));
    return 0;
}
