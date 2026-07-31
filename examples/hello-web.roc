## Uses host-owned operational telemetry and responds with a simple HTML greeting.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	gregorian: "https://cdn.jasperwoudenberg.com/roc-gregorian-v1.0.0-rc.2/Ce3xuHN92F5oGRuzjUTmm65jULAEj8pvvrTBmZJzE1M4.tar.zst",
}

import pf.Base64
import pf.Cookie
import pf.Random
import pf.Server
import pf.Stdout
import pf.UnixTime
import http.Response
import gregorian.Time

# `init!` produces this immutable context once, and every request receives it.
Context : {}

program = { init!, respond!, shutdown! }

# `init!` can validate configuration, run migrations, or prepare immutable
# startup data. This example has no startup data, so its context is `{}`.
init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	config = Server.default_config
		.with_access_log(
			Server.json_lines_access_log({
				target: Server.path_without_query,
				max_buffered_events: 128,
			}),
		)
		.with_metrics(Server.open_metrics({ at: "/metrics" }))
	Ok({ config, context: {} })
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context| {
	datetime = (Time.unix_epoch + UnixTime.now!().seconds_since_epoch()).iso8601()

	Stdout.line!("${datetime} ${Str.inspect(request.method())} ${Str.inspect(request.target())}")
		? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

	response =
		match request.target() {
			Resource({ raw_path: "/random", .. }) => {
				bytes = Random.bytes!(32)
					? |err| ServerErr("Failed to obtain random bytes: ${Str.inspect(err)}")
				Response.from_status(200).with_body(Str.to_utf8(Base64.encode(bytes)))
			}
			Resource({ raw_path: "/cookies", .. }) => {
				cookies = Cookie.parse_request(request.headers())
					? |err| ServerErr("Invalid request cookies: ${Str.inspect(err)}")
				theme = Cookie.get_unique(cookies, "theme")
					? |err| ServerErr("Ambiguous request cookie: ${Str.inspect(err)}")
				theme_value =
					match theme {
						Absent => "absent"
						Present(value) => value
					}
				session_header =
					Cookie.set_header({
						name: "__Host-session",
						value: "fresh",
						path: Present("/"),
						domain: Absent,
						max_age_seconds: Present(3600),
						secure: True,
						http_only: True,
						same_site: Present(Lax),
					})
						? |err| ServerErr("Invalid response cookie: ${Str.inspect(err)}")
				delete_theme_header =
					Cookie.delete_header({
						name: "theme",
						path: Present("/app"),
						domain: Present("example.test"),
						secure: True,
					})
						? |err| ServerErr("Invalid deletion cookie: ${Str.inspect(err)}")

				Response.from_status(200)
					.with_headers([session_header, delete_theme_header])
					.with_body(Str.to_utf8("count=${cookies.len().to_str()}; theme=${theme_value}"))
			}
			_ => Response.from_status(200).with_body(Str.to_utf8("<b>Hello from server</b><br>"))
		}

	Ok(Server.respond(response))
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
