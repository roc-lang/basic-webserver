## Streams typed SSE events from a retained Roc state machine. The host owns
## callback admission, timer scheduling, output framing, and cancellation.
app [Context, program] {
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.15.0/HcMFsVT26qeMvqWtG5rfNhVMWjceYbKh1An4uYpheBVW.tar.zst",
}

import pf.Server
import pf.Sse

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, _context|
	Ok(Server.stream(Sse.unfold!(0, transition!)))

transition! : U64, U64 => Try(Sse.Step(U64), [StreamFailed(Str)])
transition! = |state, _wake_generation|
	match state {
		0 => Ok(Emit({ event: Sse.Event.data("A"), state: 1, wake: After(50) }))
		1 => Ok(Emit({ event: Sse.Event.data("B"), state: 2, wake: Immediately }))
		2 => Ok(Wait({ state: 3, wake: After(20) }))
		3 => Ok(Emit({ event: Sse.Event.data("large-${Str.repeat("x", 20000)}"), state: 4, wake: Immediately }))
		4 => Ok(Emit({ event: Sse.Event.data("done"), state: 5, wake: Immediately }))
		5 => Ok(End)
		_ => Err(StreamFailed("invalid retained source state"))
	}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
