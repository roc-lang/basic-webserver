## Typed server-sent event sources.
##
## Applications describe one finite transition at a time. The platform host
## owns scheduling, backpressure, framing buffers, compression, cancellation,
## and the lifetime of the retained source between transitions.
Sse :: [].{
	Source := [Source(Box(U64 => StepToHost))]

	EventId := [AbsentEventId, ClearEventId, SetEventId(Str)]

	Retry := [NoRetry, RetryAfter(U64)]

	EventOptions := {
		id : EventId,
		retry : Retry,
	}

	default_event_options : EventOptions
	default_event_options = { id: AbsentEventId, retry: NoRetry }

	## Validate an SSE event ID. IDs become `Last-Event-ID` request header
	## values on reconnect, so NUL and line endings are rejected rather than
	## normalized.
	event_id : Str -> Try(EventId, [InvalidEventId])
	event_id = |value|
		if Str.contains(value, "\r") or Str.contains(value, "\n") or List.any(Str.to_utf8(value), |byte| byte == 0) {
			Err(InvalidEventId)
		} else {
			Ok(SetEventId(value))
		}

	## Emit an empty `id:` field, clearing Datastar's retained reconnect ID.
	clear_event_id : EventId
	clear_event_id = ClearEventId

	## Ask the client to use a new reconnect delay, in milliseconds.
	retry_after : U64 -> Retry
	retry_after = |milliseconds| RetryAfter(milliseconds)

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
				frame = Str.with_capacity(
					17 + Str.count_utf8_bytes(safe_name) + Str.count_utf8_bytes(key) + Str.count_utf8_bytes(value),
				)
					.concat("event: ")
					.concat(safe_name)
					.concat("\ndata: ")
					.concat(key)
					.concat(" ")
					.concat(value)
					.concat("\n\n")
				Event(Str.to_utf8(frame))
			}
		}

		## Construct one named SSE event from already-keyed data fields. Event
		## names have line endings removed so they cannot create a second SSE
		## field. Every logical line in a data field is emitted as its own
		## `data:` line.
		named : Str, List(Str) -> Event
		named = |name, values| named_with(name, values, default_event_options)

		## Construct a named event with optional reconnect ID and retry metadata.
		## The ID is already validated by [`event_id`](#Sse.event_id); all data
		## values remain canonical `data:` fields.
		named_with : Str, List(Str), EventOptions -> Event
		named_with = |name, values, options| {
			safe_name = Str.join_with(Str.split_on(Str.join_with(Str.split_on(name, "\r"), ""), "\n"), "")
			id_fields =
				match options.id {
					AbsentEventId => []
					ClearEventId => ["id:"]
					SetEventId(value) => ["id: ${value}"]
				}
			retry_fields =
				match options.retry {
					NoRetry => []
					RetryAfter(milliseconds) => ["retry: ${U64.to_str(milliseconds)}"]
				}
			fields = values.map(
				|value| {
					lf = Str.join_with(Str.split_on(value, "\r\n"), "\n")
					normalized = Str.join_with(Str.split_on(lf, "\r"), "\n")
					lines = Str.split_on(normalized, "\n").map(|line| "data: ${line}")
					Str.join_with(lines, "\n")
				},
			)
			lines = List.concat(List.concat(["event: ${safe_name}"], id_fields), List.concat(retry_fields, fields))
			Event(Str.to_utf8("${Str.join_with(lines, "\n")}\n\n"))
		}

		## Construct one SSE data event. Embedded CR, LF, and CRLF line endings
		## are normalized and emitted as one `data:` field per logical line.
		data : Str -> Event
		data = |value| {
			if Bool.not(Str.contains(value, "\r")) and Bool.not(Str.contains(value, "\n")) {
				frame = Str.with_capacity(8 + Str.count_utf8_bytes(value))
					.concat("data: ")
					.concat(value)
					.concat("\n\n")
				return Event(Str.to_utf8(frame))
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
	unfold! : state, (state => Try(Step(state), err)) => Source
	unfold! = |initial_state, transition!| {
		from_state : state -> Source
		from_state = |state|
			Source(
				Box.box(
					|_wake_generation| {
						match transition!(state) {
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
