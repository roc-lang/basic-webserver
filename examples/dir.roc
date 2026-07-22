app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Stderr
import pf.Env
import pf.Http
import pf.Path
import http.Response

# To run this example: check the root README.md

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = || {
    result! = || {
        cwd = Env.cwd!()?
        Stdout.line!("The current working directory is ${Path.display(cwd)}")?

        Env.set_cwd!(Path.utf8("examples/"))?
        Stdout.line!("Set cwd to examples/")?

        paths = Path.list!(Path.utf8("./"))?
        paths_str = Str.join_with(paths.map(Path.display), "\n")
        Stdout.line!("The paths are;\n${paths_str}")?

        Ok({})
    }

    match result!() {
        Ok(_) => Ok({})
        Err(err) => {
            Stderr.line!("Error during directory operations: ${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok(Response.from_status(200).with_body(Str.to_utf8("See example in init! function.")))
