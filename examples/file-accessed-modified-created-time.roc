app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.Stdout
import pf.Stderr
import pf.Http
import pf.File
import pf.Utc
import http.Response

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || {
    result = || {
        file = "LICENSE"

        # NOTE: these functions will not work if basic-webserver was built with musl, which is the case for the normal tar.br URL release.
        # See https://github.com/roc-lang/basic-webserver?tab=readme-ov-file#developing--building-locally to build basic-webserver without musl.

        time_modified = Utc.to_millis_since_epoch(File.time_modified!(file)?)
        time_accessed = Utc.to_millis_since_epoch(File.time_accessed!(file)?)
        time_created = Utc.to_millis_since_epoch(File.time_created!(file)?)

        Stdout.line!("${file} file time metadata:\n    Modified: ${time_modified.to_str()} ms since epoch\n    Accessed: ${time_accessed.to_str()} ms since epoch\n    Created: ${time_created.to_str()} ms since epoch")?

        Ok({})
    }

    match result() {
        Ok(_) => Ok({})
        Err(err) => {
            _ = Stderr.line!("Error reading file time metadata: ${Str.inspect(err)}")
            Err(Exit(1))
        }
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok(Response.from_status(200).with_body(Str.to_utf8("See example in init! function.")))
