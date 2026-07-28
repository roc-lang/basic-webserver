## Serves public assets without entering Roc and authorizes one attachment in Roc.
app [Context, program] {
	pf: platform "../platform/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Path
import pf.Server
import pf.Stdout
import http.Response

Context : {
	downloads : Server.FileRoot,
	report : Server.RelativeFile,
}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = || {
	assets = Server.file_root_with_cache({
		id: "assets",
		path: Path.utf8("assets"),
		cache: Server.public_for(3600),
	})
	downloads = Server.file_root({
		id: "downloads",
		path: Path.utf8("downloads"),
	})
	report = 
		Server.relative_file("reports/annual report.txt")
			.map_err(|_| Exit(1))?
	favicon = 
		Server.relative_file("favicon.ico")
			.map_err(|_| Exit(1))?

	config = 
		Server.default_config
			.with_file_roots([assets, downloads])
			.with_native_routes({
				files: [
					Server.static_mount({ at: "/assets", files: assets }),
					Server.static_file({ at: "/favicon.ico", files: assets, relative: favicon }),
				],
				liveness: [],
				readiness: [],
			})

	Ok({
		config,
		context: { downloads, report },
	})
}

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |request, context| {
	target = request.target()
	Stdout.line!("Roc handled ${target}")
		? |err| ServerErr("Failed to log request: ${Str.inspect(err)}")

	if target == "/download?token=secret" {
		Ok(
			Server.file_response_with({
				files: context.downloads,
				relative: context.report,
				disposition: Server.attachment("annual report.txt"),
				cache: Server.override_cache(Server.no_store),
			}),
		)
	} else if target == "/download" {
		Ok(
			Server.respond(
				Response.from_status(403)
					.with_body(Str.to_utf8("Download denied")),
			),
		)
	} else {
		Ok(
			Server.respond(
				Response.from_status(404)
					.with_body(Str.to_utf8("Roc fallback")),
			),
		)
	}
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_reason, _context| Ok({})
