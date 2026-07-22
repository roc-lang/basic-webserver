app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Stderr
import pf.Http
import pf.Path
import http.Response

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || {
    result! = || {
        file = Path.utf8("LICENSE")

        is_executable = Path.is_executable!(file)?

        is_readable = Path.is_readable!(file)?

        is_writable = Path.is_writable!(file)?

        Stdout.line!("${Path.display(file)} file permissions:\n    Executable: ${bool_to_str(is_executable)}\n    Readable: ${bool_to_str(is_readable)}\n    Writable: ${bool_to_str(is_writable)}")?

        Ok({})
    }

    match result!() {
        Ok(_) => Ok({})
        Err(err) => {
            Stderr.line!("Error reading file permissions: ${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }
}

bool_to_str : Bool -> Str
bool_to_str = |value| if value { "Bool.true" } else { "Bool.false" }

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok(Response.from_status(200).with_body(Str.to_utf8("See example in init! function.")))
