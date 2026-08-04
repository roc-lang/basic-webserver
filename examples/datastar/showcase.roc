## Reproduces the public non-Rocket Datastar examples as executable Roc API probes.
app [Context, program] {
	pf: platform "../../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Datastar
import pf.Server
import http.Response
import "datastar-v1.0.2.js" as datastar_js : List(U8)

Context : {}

ActiveSearchSignals : { activeSearch : Str }

Contact : { first : Str, last : Str, search : Str }

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || Ok({ config: Server.default_config, context: {} })

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, _context| {
	path =
		match request.target() {
			Resource({ raw_path, .. }) => raw_path
			_ => ""
		}

	match (request.method(), path) {
		(GET, "/") => Ok(Server.respond(html_response(index_page)))
		(GET, "/datastar.js") => Ok(Server.respond(javascript_response(datastar_js)))
		(GET, "/examples/active_search") => Ok(Server.respond(html_response(active_search_page)))
		(GET, "/examples/active_search/search") => active_search!(request)
		_ => Ok(Server.respond(text_response(404, "Example not found")))
	}
}

active_search! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
active_search! = |request| {
	signals_result : Try(ActiveSearchSignals, Datastar.SignalsError)
	signals_result = Datastar.read_signals!(request)
	signals =
		match signals_result {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(text_response(400, "Invalid Datastar signals: ${Str.inspect(err)}")))
		}

	Ok(Datastar.respond([Datastar.patch_elements(active_search_demo(signals.activeSearch))]))
}

contacts : List(Contact)
contacts = [
	{ first: "Abraham", last: "Jakubowski", search: "abraham jakubowski" },
	{ first: "Adriel", last: "Glover", search: "adriel glover" },
	{ first: "Agustin", last: "Leannon", search: "agustin leannon" },
	{ first: "Aimee", last: "Breitenberg", search: "aimee breitenberg" },
	{ first: "Alana", last: "Dach", search: "alana dach" },
	{ first: "Alayna", last: "Fay", search: "alayna fay" },
	{ first: "Albertha", last: "Rodriguez", search: "albertha rodriguez" },
	{ first: "Alek", last: "Grimes", search: "alek grimes" },
	{ first: "Alexandria", last: "Reichert", search: "alexandria reichert" },
	{ first: "Alfreda", last: "Kozey", search: "alfreda kozey" },
	{ first: "Bryana", last: "Bernier", search: "bryana bernier" },
	{ first: "Jensen", last: "Kassulke", search: "jensen kassulke" },
	{ first: "Amparo", last: "O'Keefe", search: "amparo o'keefe" },
	{ first: "Cornell", last: "Price", search: "cornell price" },
	{ first: "William", last: "Ankunding", search: "william ankunding" },
]

active_search_demo : Str -> Str
active_search_demo = |query| {
	needle = ascii_lower(query)
	matching =
		if needle.is_empty() {
			contacts
		} else {
			contacts.keep_if(|contact| Str.contains(contact.search, needle))
		}
	rows =
		Str.join_with(
			matching.map(|contact| "<tr><td>${contact.first}</td><td>${contact.last}</td></tr>"),
			"",
		)

	\\<div id="demo">
	\\    <input type="text" placeholder="Search..." data-bind:active-search data-on:input__debounce.200ms="@get('/examples/active_search/search')">
	\\    <table>
	\\        <thead><tr><th>First Name</th><th>Last Name</th></tr></thead>
	\\        <tbody>${rows}</tbody>
	\\    </table>
	\\</div>
}

page : Str, Str -> Str
page = |title, content|
	\\<!doctype html>
	\\<html lang="en">
	\\<head>
	\\    <meta charset="utf-8">
	\\    <meta name="viewport" content="width=device-width, initial-scale=1">
	\\    <title>${title} · Roc + Datastar</title>
	\\    <script type="module" src="/datastar.js"></script>
	\\    <style>
	\\        :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
	\\        body { max-width: 54rem; margin: 3rem auto; padding: 0 1rem; }
	\\        nav { display: flex; gap: 1rem; margin-bottom: 2rem; }
	\\        fieldset { padding: 1.5rem; }
	\\        input { width: min(24rem, 100%); padding: .65rem; }
	\\        table { width: 100%; margin-top: 1rem; border-collapse: collapse; }
	\\        th, td { text-align: left; padding: .5rem; border-bottom: 1px solid #8886; }
	\\        code { background: #8882; padding: .1rem .3rem; }
	\\    </style>
	\\</head>
	\\<body>
	\\    <nav><a href="/">All examples</a><a href="https://data-star.dev/examples/" rel="noreferrer">Datastar originals</a></nav>
	\\    ${content}
	\\</body>
	\\</html>

index_page : Str
index_page = page(
	"Examples",
	\\<h1>Roc + Datastar examples</h1>
	\\<p>Executable reproductions used to evaluate basic-webserver's Datastar API.</p>
	\\<ol><li><a href="/examples/active_search">Active Search</a></li></ol>
	,
)

active_search_page : Str
active_search_page = page(
	"Active Search",
	\\<h1>Active Search</h1>
	\\<p>Searches a server-owned contact list as the bound signal changes.</p>
	\\<fieldset><legend>Demo</legend>${active_search_demo("")}</fieldset>
	\\<h2>What this validates</h2>
	\\<p><code>Datastar.read_signals!</code> decodes GET query signals and <code>Datastar.respond</code> returns a finite typed patch without occupying a retained-stream slot.</p>
	,
)

ascii_lower : Str -> Str
ascii_lower = |value|
	Str.from_utf8_lossy(
		Str.to_utf8(value).map(
			|byte|
				if byte >= 65 and byte <= 90 {
					byte + 32
				} else {
					byte
				},
		),
	)

html_response : Str -> Response
html_response = |body|
	Response.from_status(200)
		.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
		.with_body(Str.to_utf8(body))

javascript_response : List(U8) -> Response
javascript_response = |body|
	Response.from_status(200)
		.with_headers([{ name: "Content-Type", value: "text/javascript; charset=utf-8" }])
		.with_body(body)

text_response : U16, Str -> Response
text_response = |status, body|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
		.with_body(Str.to_utf8(body))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
