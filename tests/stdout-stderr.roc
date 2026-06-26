app [Model, program] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Http

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}|
    match run_tests!({}) {
        Ok(_) => {
            _ = Stdout.line!("Ran all tests.")
            Err(Exit(0))
        }
        Err(err) => {
            _ = Stderr.line!("Test run failed:\n\t${Str.inspect(err)}")
            Err(Exit(1))
        }
    }

run_tests! : {} => Try({}, [StdoutErr(_), StderrErr(_), ..])
run_tests! = |{}| {
    Stdout.write!("stdout\n")?
    Stderr.write!("stderr\n")?

    Stdout.write_bytes!(Str.to_utf8("stdout bytes\n"))?
    Stderr.write_bytes!(Str.to_utf8("stderr bytes\n"))?

    Stdout.line!("stdout line")?
    Stderr.line!("stderr line")?

    Ok({})
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok({ status: 200, headers: [], body: Str.to_utf8("I am a test.") })
