# Native work lifetime audit

Hosted effects are synchronous from Roc's perspective, but some operating
system calls require native helper work. A public timeout means that the caller
stops waiting; it does not claim that already-started external work was undone.

The production helper-work inventory is:

| Work | Bound and ownership | Timeout and shutdown |
| --- | --- | --- |
| Command processes and output readers | Eight active commands and 32 queued calls. Reader threads own their pipe handles. | A limit terminates the process tree, waits for the child, and joins both readers before returning. Shutdown drains the Roc handler that owns the command. |
| Raw TCP DNS | At most 64 active resolver threads and 64 queued calls. The hostname is owned and the active permit moves into the resolver thread. | Returning `TimedOut` does not cancel `getaddrinfo`; its permit remains charged. Subsystem shutdown waits one second for resolvers, then process exit is the hard-stop policy. |
| Outbound HTTP DNS | At most 64 active blocking lookups and 256 queued lookups. The hostname is owned and the active permit moves into the blocking closure. | Dropping the request future does not release resolver capacity. Outbound runtime shutdown waits one second, then process exit is the hard-stop policy for an OS lookup that has not returned. |
| Outbound HTTP transport tasks | Hyper owns connection and pool tasks on the dedicated outbound runtime; request inputs are owned before admission. | Ordinary request futures are cancellation-safe. The client is dropped after Roc callbacks and `shutdown!`, then its runtime is joined with the same one-second hard deadline used for DNS. |
| Request-body pumps | One task per admitted request, bounded by server request and connection limits. The task owns Hyper's body and bounded channel sender. | Handler completion or shutdown cancels the body state; runtime teardown cancels any task that has not observed it yet. No Roc or invocation-local pointer is retained. |
| Server connections and signal watcher | Connection tasks hold bounded connection permits and live in a `JoinSet`; there is one signal task. | Connections are joined during graceful drain or aborted immediately before hard process exit. The signal task is explicitly aborted after draining. |
| Roc handler workers | Active and queued counts come from `Server.Config`; each blocking worker owns its request guard and retained immutable context. | Graceful shutdown drains all workers. Exceeding the configured drain deadline forces process exit instead of destroying context still in use. |
| Shutdown watchdog | Exactly one thread while `shutdown!` runs. It owns only its completion receiver and timeout. | It is joined when the hook returns; exceeding the hook deadline forces process exit. |

Test-only threads and tasks are excluded. Command child processes are included
because their lifetime is a production concern even though they are not Rust
helper threads.
