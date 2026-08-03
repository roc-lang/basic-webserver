## Typed server-sent event sources.
##
## Applications describe one finite transition at a time. The platform host
## owns scheduling, backpressure, framing buffers, compression, cancellation,
## and the lifetime of the retained source between transitions.
Sse :: [].{
	Source := [Source(Box(U64 => StepToHost))]

	Event := [Event(List(U8))].{

		## Construct a named SSE event containing one keyed data value. The common
		## single-line path creates the complete frame once; multiline values fall
		## back to canonical repeated keyed fields.
		keyed : Str, Str, Str -> Event
		keyed = |name, key, value| {
			safe_name =
				if Str.contains(name, "\r") or Str.contains(name, "\n") {
					Str.join_with(Str.split_on(Str.join_with(Str.split_on(name, "\r"), ""), "\n"), "")
				} else {
					name
				}

			if Str.contains(value, "\r") or Str.contains(value, "\n") {
				lf = Str.join_with(Str.split_on(value, "\r\n"), "\n")
				normalized = Str.join_with(Str.split_on(lf, "\r"), "\n")
				fields = Str.split_on(normalized, "\n").map(|line| "${key} ${line}")
				named(safe_name, fields)
			} else {
				Event(Str.to_utf8("event: ${safe_name}\ndata: ${key} ${value}\n\n"))
			}
		}

		## Construct one named SSE event from already-keyed data fields. Event
		## names have line endings removed so they cannot create a second SSE
		## field. Every logical line in a data field is emitted as its own
		## `data:` line.
		named : Str, List(Str) -> Event
		named = |name, values| {
			safe_name = Str.join_with(Str.split_on(Str.join_with(Str.split_on(name, "\r"), ""), "\n"), "")
			fields = values.map(
				|value| {
					lf = Str.join_with(Str.split_on(value, "\r\n"), "\n")
					normalized = Str.join_with(Str.split_on(lf, "\r"), "\n")
					lines = Str.split_on(normalized, "\n").map(|line| "data: ${line}")
					Str.join_with(lines, "\n")
				},
			)
			Event(Str.to_utf8("event: ${safe_name}\n${Str.join_with(fields, "\n")}\n\n"))
		}

		## Construct one SSE data event. Embedded CR, LF, and CRLF line endings
		## are normalized and emitted as one `data:` field per logical line.
		data : Str -> Event
		data = |value| {
			if Bool.not(Str.contains(value, "\r")) and Bool.not(Str.contains(value, "\n")) {
				return Event(Str.to_utf8("data: ${value}\n\n"))
			}
			lf = Str.join_with(Str.split_on(value, "\r\n"), "\n")
			normalized = Str.join_with(Str.split_on(lf, "\r"), "\n")
			fields = Str.split_on(normalized, "\n").map(|line| "data: ${line}")
			Event(Str.to_utf8("${Str.join_with(fields, "\n")}\n\n"))
		}
	}

	Wake := [Immediately, After(U64)].{
		to_host : Wake -> U64
		to_host = |wake|
			match wake {
				Immediately => 0
				After(milliseconds) => milliseconds
			}
	}

	Step(state) := [
		Emit({ event : Event, state : state, wake : Wake }),
		Wait({ state : state, wake : Wake }),
		End,
	]

	## Retain typed application state behind a private affine source. Every
	## invocation returns the next source owner; the host never copies or
	## reconstructs application state.
	unfold! : state, (state, U64 => Try(Step(state), err)) => Source
	unfold! = |initial_state, transition!| {
		from_state : state -> Source
		from_state = |state|
			Source(
				Box.box(
					|wake_generation| {
						match transition!(state, wake_generation) {
							Ok(Emit({ event: Event(item), state: next_state, wake })) =>
								EmitToHost({
									item,
									source: from_state(next_state),
									wait_millis: Wake.to_host(wake),
								})
							Ok(Wait({ state: next_state, wake })) =>
								WaitToHost({
									source: from_state(next_state),
									wait_millis: Wake.to_host(wake),
								})
							Ok(End) => EndToHost
							Err(err) => ErrorToHost(Str.inspect(err))
						}
					},
				),
			)

		from_state(initial_state)
	}

	## Platform ABI operation; not an application API.
	advance_for_host! : Source, U64 => StepToHost
	advance_for_host! = |Source(boxed_step), wake_generation|
		(Box.unbox(boxed_step))(wake_generation)

	## Platform ABI operation; consuming the value lets ARC release the complete
	## retained application state graph.
	drop_source_for_host! : Source => {}
	drop_source_for_host! = |_source| {}

	## Platform ABI operation used when a returned step cannot be installed.
	drop_step_for_host! : StepToHost => {}
	drop_step_for_host! = |_step| {}

	StepToHost := [
		EmitToHost({ item : List(U8), source : Source, wait_millis : U64 }),
		WaitToHost({ source : Source, wait_millis : U64 }),
		EndToHost,
		ErrorToHost(Str),
	]

}
