app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Stderr
import pf.Http
import pf.Path
import pf.Utc
import http.Response

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || {
    result! = || {
        file = Path.utf8("LICENSE")

        time_modified = Utc.to_iso_8601(Path.time_modified!(file)?)
        time_accessed = Utc.to_iso_8601(Path.time_accessed!(file)?)
        time_created = Utc.to_iso_8601(Path.time_created!(file)?)

        Stdout.line!("${Path.display(file)} file time metadata:\n    Modified: ${time_modified}\n    Accessed: ${time_accessed}\n    Created: ${time_created}")?

        Ok({})
    }

    match result!() {
        Ok(_) => Ok({})
        Err(err) => {
            Stderr.line!("Error reading file time metadata: ${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok(Response.from_status(200).with_body(Str.to_utf8("See example in init! function.")))
