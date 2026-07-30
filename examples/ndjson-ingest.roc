## Streams newline-delimited JSON events into SQLite in short, retry-safe
## batches without materializing the complete HTTP request body.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Path
import pf.Server
import pf.Sqlite
import http.Header
import http.Response

## Set `DB_PATH` to choose the SQLite database. Events have client-provided
## stable IDs, so retrying a partially committed request does not duplicate
## records.

Context : Sqlite.Db

Event : {
	id : Str,
	source : Str,
	value : I64,
}

DecodedEvent : {
	encoded_bytes : U64,
	event : Event,
}

DecoderData : {
	line : List(U8),
	line_number : U64,
	max_line_bytes : U64,
}

## Incremental NDJSON framing state. Each push returns the decoder to use for
## the next transport chunk; finish rejects an unterminated final record.
Decoder := [DecoderState(DecoderData)].{
	init : U64 -> Decoder
	init = |line_limit|
		DecoderState({
			line: [],
			line_number: 1,
			max_line_bytes: line_limit,
		})

	push : Decoder, List(U8) -> Try({ decoder : Decoder, events : List(DecodedEvent) }, DecodeError)
	push = |DecoderState(data), bytes|
		decode_bytes(data, bytes, [])
			.map_ok(
				|result| {
					decoder: DecoderState(result.decoder),
					events: result.events,
				},
			)

	finish : Decoder -> Try({}, DecodeError)
	finish = |DecoderState(data)|
		if data.line.is_empty() {
			Ok({})
		} else {
			Err(MissingFinalNewline(data.line_number))
		}
}

IngestData : {
	batch : List(DecodedEvent),
	batch_bytes : U64,
	committed : U64,
	decoder : Decoder,
}

## Request-local ingestion state. push! may commit complete bounded batches;
## finish! validates EOF and commits the final partial batch.
Ingest := [IngestState(IngestData)].{
	start : U64 -> Ingest
	start = |line_limit|
		IngestState({
			batch: [],
			batch_bytes: 0,
			committed: 0,
			decoder: Decoder.init(line_limit),
		})

	committed : Ingest -> U64
	committed = |IngestState(data)| data.committed

	push! : Ingest, Sqlite.Db, List(U8) => Try(Ingest, IngestError)
	push! = |IngestState(data), db, chunk| {
		decoded = data.decoder.push(chunk)
			? |err| DecodeFailed({ committed: data.committed, err })
		with_decoder = { ..data, decoder: decoded.decoder }
		ingest_add_events!(with_decoder, db, decoded.events)
			.map_ok(|next| IngestState(next))
	}

	finish! : Ingest, Sqlite.Db => Try(U64, IngestError)
	finish! = |IngestState(data), db| {
		data.decoder.finish()
			? |err| DecodeFailed({ committed: data.committed, err })
		final = ingest_flush!(data, db)?
		Ok(final.committed)
	}
}

DecodeError : [
	BlankLine(U64),
	InvalidEvent(U64),
	InvalidJsonLine(U64),
	InvalidUtf8(U64),
	LineTooLarge({ limit_bytes : U64, line_number : U64 }),
	MissingFinalNewline(U64),
]

IngestError : [
	DatabaseFailed({ committed : U64, detail : Str }),
	DecodeFailed({ committed : U64, err : DecodeError }),
]

decode_error_to_str : DecodeError -> Str
decode_error_to_str = |err|
	match err {
		BlankLine(line) => "Line ${U64.to_str(line)} is empty."
		InvalidEvent(line) => "Line ${U64.to_str(line)} must have non-empty id and source fields."
		InvalidJsonLine(line) => "Line ${U64.to_str(line)} is not a valid event JSON object."
		InvalidUtf8(line) => "Line ${U64.to_str(line)} is not valid UTF-8."
		LineTooLarge({ line_number, limit_bytes }) => "Line ${U64.to_str(line_number)} exceeds ${U64.to_str(limit_bytes)} bytes."
		MissingFinalNewline(line) => "Line ${U64.to_str(line)} is missing its final newline."
	}

ingest_error_status : IngestError -> U16
ingest_error_status = |err|
	match err {
		DatabaseFailed(_) => 503
		DecodeFailed(_) => 400
	}

ingest_error_committed : IngestError -> U64
ingest_error_committed = |err|
	match err {
		DatabaseFailed({ committed, detail: _ }) => committed
		DecodeFailed({ committed, err: _ }) => committed
	}

ingest_error_to_str : IngestError -> Str
ingest_error_to_str = |ingest_err|
	match ingest_err {
		DatabaseFailed({ committed: _, detail }) => "Database batch failed: ${detail}"
		DecodeFailed({ committed: _, err }) => decode_error_to_str(err)
	}

program = { init!, respond!, shutdown! }

max_body_bytes : U64
max_body_bytes = 32 * 1024 * 1024

max_line_bytes : U64
max_line_bytes = 64 * 1024

max_batch_bytes : U64
max_batch_bytes = 256 * 1024

max_batch_records : U64
max_batch_records = 100

decode_bytes : DecoderData, List(U8), List(DecodedEvent) -> Try({ decoder : DecoderData, events : List(DecodedEvent) }, DecodeError)
decode_bytes = |decoder, bytes, events|
	match bytes {
		[] => Ok({ decoder, events })
		[byte, .. as rest] =>
			if byte == '\n' {
				decoded = decode_line(decoder)?
				decode_bytes(
					{
						..decoder,
						line: [],
						line_number: decoder.line_number + 1,
					},
					rest,
					events.append(decoded),
				)
			} else if decoder.line.len() >= decoder.max_line_bytes {
				Err(
					LineTooLarge({
						limit_bytes: decoder.max_line_bytes,
						line_number: decoder.line_number,
					}),
				)
			} else {
				decode_bytes(
					{ ..decoder, line: decoder.line.append(byte) },
					rest,
					events,
				)
			}
		}

decode_line : DecoderData -> Try(DecodedEvent, DecodeError)
decode_line = |decoder| {
	line =
		match List.last(decoder.line) {
			Ok('\r') => decoder.line.drop_last(1)
			_ => decoder.line
		}
	if line.is_empty() {
		return Err(BlankLine(decoder.line_number))
	}

	json =
		match Str.from_utf8(line) {
			Ok(value) => value
			Err(_) => return Err(InvalidUtf8(decoder.line_number))
		}

	parsed : Try(Event, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(json)
	event =
		match parsed {
			Ok(value) => value
			Err(_) => return Err(InvalidJsonLine(decoder.line_number))
		}
	if Str.is_empty(event.id) or Str.is_empty(event.source) {
		Err(InvalidEvent(decoder.line_number))
	} else {
		Ok({
			encoded_bytes: decoder.line.len() + 1,
			event,
		})
	}
}

ingest_add_events! : IngestData, Sqlite.Db, List(DecodedEvent) => Try(IngestData, IngestError)
ingest_add_events! = |ingest, db, events|
	match events {
		[] => Ok(ingest)
		[first, .. as rest] => {
			ready =
				if ingest.batch.is_empty() {
					ingest
				} else if ingest.batch.len() >= max_batch_records or ingest.batch_bytes + first.encoded_bytes > max_batch_bytes {
					ingest_flush!(ingest, db)?
				} else {
					ingest
				}
			next = {
				..ready,
				batch: ready.batch.append(first),
				batch_bytes: ready.batch_bytes + first.encoded_bytes,
			}
			flushed =
				if next.batch.len() >= max_batch_records or next.batch_bytes >= max_batch_bytes {
					ingest_flush!(next, db)?
				} else {
					next
				}
			ingest_add_events!(flushed, db, rest)
		}
	}

ingest_flush! : IngestData, Sqlite.Db => Try(IngestData, IngestError)
ingest_flush! = |ingest, db| {
	if ingest.batch.is_empty() {
		return Ok(ingest)
	}

	transaction =
		Sqlite.begin!(db, Immediate)
			? |err| DatabaseFailed({ committed: ingest.committed, detail: Str.inspect(err) })
	insert_batch!(transaction, ingest.batch)
		? |err| DatabaseFailed({ committed: ingest.committed, detail: Str.inspect(err) })
	transaction.commit!()
		? |err| DatabaseFailed({ committed: ingest.committed, detail: Str.inspect(err) })

	Ok({
		..ingest,
		batch: [],
		batch_bytes: 0,
		committed: ingest.committed + ingest.batch.len(),
	})
}

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	db_path =
		match Env.var!("DB_PATH") {
			Ok(path) => Path.from_os_str(path)
			Err(_) => Path.utf8("./examples/events.db")
		}
	db = Sqlite.open!(Sqlite.default_config(db_path)) ? |_| Exit(2)
	ensure_schema!(db) ? |_| Exit(3)

	config =
		Server.with_request_body_limits(
			Server.default_config,
			{
				max_bytes: max_body_bytes,
				chunk_bytes: Server.default_body_chunk_bytes,
				buffered_chunks: Server.default_buffered_body_chunks,
			},
		)
	Ok({ config, context: db })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, db| {
	response =
		match (request.method(), request.target()) {
			(POST, Resource({ raw_path: "/events", .. })) => ingest_events!(db, request)
			(GET, Resource({ raw_path: "/events/count", .. })) => event_count!(db)
			_ => text_response(404, "Not found.")
		}

	Ok(Server.respond(response))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _db| Ok({})

ingest_events! : Sqlite.Db, Server.Request => Response
ingest_events! = |db, request| {
	if Bool.not(has_ndjson_content_type(request.headers())) {
		return text_response(415, "Content-Type must be application/x-ndjson.")
	}

	folded =
		request
			.body()
			.with_limit(max_body_bytes)
			.fold_chunks!(
				Ingest.start(max_line_bytes),
				|ingest, chunk| ingest.push!(db, chunk),
			)

	match folded {
		Err(ChunkReadErr({ err, state })) =>
			ingest_error_response(
				400,
				state.committed(),
				"Request body failed: ${Str.inspect(err)}",
			)
		Err(ChunkStepErr(err)) => ingest_failure_response(err)
		Ok(ingest) =>
			match ingest.finish!(db) {
				Ok(committed) => committed_response(200, committed)
				Err(err) => ingest_failure_response(err)
			}
		}
}

insert_batch! : Sqlite.Transaction, List(DecodedEvent) => Try({}, Sqlite.QueryError)
insert_batch! = |transaction, events|
	match events {
		[] => Ok({})
		[{ event, encoded_bytes: _ }, .. as rest] => {
			transaction.execute!({
				query: \\INSERT INTO events (id, source, value)
					\\VALUES (:id, :source, :value)
					\\ON CONFLICT(id) DO NOTHING;
				,
				params: {
					id: event.id,
					source: event.source,
					value: event.value,
				},
			})?
			insert_batch!(transaction, rest)
		}
	}

ensure_schema! : Sqlite.Db => Try({}, Sqlite.QueryError)
ensure_schema! = |db|
	Sqlite.execute!({
		db,
		query: \\CREATE TABLE IF NOT EXISTS events (
			\\    id TEXT PRIMARY KEY,
			\\    source TEXT NOT NULL,
			\\    value INTEGER NOT NULL
			\\);
		,
		params: {},
	})

event_count! : Sqlite.Db => Response
event_count! = |db| {
	result : Try({ count : I64 }, Sqlite.QueryError)
	result = Sqlite.query!({
		db,
		query: "SELECT COUNT(*) AS count FROM events;",
		params: {},
		limits: Sqlite.default_query_limits,
	})
	match result {
		Ok(row) =>
			Response.from_status(200)
				.with_headers([{ name: "Content-Type", value: "application/json; charset=utf-8" }])
				.with_body(Str.to_utf8("{\"count\":${I64.to_str(row.count)}}"))
		Err(err) => text_response(503, "Failed to query events: ${Str.inspect(err)}")
	}
}

has_ndjson_content_type : List(Header.Header) -> Bool
has_ndjson_content_type = |headers|
	match headers {
		[] => Bool.False
		[{ name, value }, .. as rest] =>
			if (name == "Content-Type" or name == "content-type") and value == "application/x-ndjson" {
				Bool.True
			} else {
				has_ndjson_content_type(rest)
			}
		}

ingest_failure_response : IngestError -> Response
ingest_failure_response = |err|
	ingest_error_response(ingest_error_status(err), ingest_error_committed(err), ingest_error_to_str(err))

ingest_error_response : U16, U64, Str -> Response
ingest_error_response = |status, committed, message|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "application/json; charset=utf-8" }])
		.with_body(Str.to_utf8(Json.to_str({ committed, error: message })))

committed_response : U16, U64 -> Response
committed_response = |status, committed|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "application/json; charset=utf-8" }])
		.with_body(Str.to_utf8("{\"committed\":${U64.to_str(committed)}}"))

text_response : U16, Str -> Response
text_response = |status, body|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
		.with_body(Str.to_utf8(body))

expect {
	first = Str.to_utf8("{\"id\":\"evt-1\",\"source\":\"caf").append(195)
	second = [169].concat(Str.to_utf8("\",\"value\":1}\r\n{\"id\":\"evt-2\",\"source\":\"sensor\",\"value\":2}\n"))
	initial = Decoder.init(1024)

	match initial.push(first) {
		Err(_) => Bool.False
		Ok(partial) =>
			match partial.decoder.push(second) {
				Err(_) => Bool.False
				Ok(done) =>
					match done.decoder.finish() {
						Err(_) => Bool.False
						Ok({}) => done.events.map(|item| item.event.id) == ["evt-1", "evt-2"]
					}
				}
		}
}

expect {
	line = Str.to_utf8("{\"id\":\"evt-1\",\"source\":\"sensor\",\"value\":1}")
	exact = Decoder.init(line.len())
	too_small = Decoder.init(line.len() - 1)

	match exact.push(line.append('\n')) {
		Err(_) => Bool.False
		Ok(result) =>
			match too_small.push(line) {
				Err(LineTooLarge({ limit_bytes, line_number })) =>
					result.events.len() == 1
						and limit_bytes == line.len() - 1
							and line_number == 1
				_ => Bool.False
			}
		}
}

expect {
	line = Str.to_utf8("{\"id\":\"evt-1\",\"source\":\"sensor\",\"value\":1}")

	match Decoder.init(1024).push(line) {
		Err(_) => Bool.False
		Ok(partial) =>
			match partial.decoder.finish() {
				Err(MissingFinalNewline(line_number)) => line_number == 1
				_ => Bool.False
			}
		}
}
