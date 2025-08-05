app [Model, init!, respond!] { 
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Stderr
import pf.Http exposing [Request, Response]

Model : {}

init! : {} => Result Model _
init! = |{}|
    when run_tests!({}) is
        Ok(_) ->
            Err(Exit(0, "Ran all tests."))
        Err(err) ->
            Err(Exit(1, "Test run failed:\n\t${Inspect.to_str(err)}"))

run_tests! : {} => Result {} _
run_tests! = |{}|
    Stdout.write!("stdout\n")?
    Stderr.write!("stderr\n")?

    Stdout.write_bytes!(Str.to_utf8("stdout bytes\n"))?
    Stderr.write_bytes!(Str.to_utf8("stderr bytes\n"))?

    Stdout.line!("stdout line")?
    Stderr.line!("stderr line")?

    Ok({})

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |_, _|

    Ok(
        {
            status: 200,
            headers: [],
            body: Str.to_utf8("I am a test."),
        },
    )