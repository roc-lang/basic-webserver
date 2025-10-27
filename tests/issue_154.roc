app [Model, init!, respond!] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.MultipartFormData

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
    Stdout.line!("Testing parse_form_url_encoded preserves literal plus signs.")?

    encoded = "message=This+%2B+is+a+plus"
    Stdout.line!("Encoded input: ${encoded}")?

    dict =
        (
            encoded
            |> Str.to_utf8
            |> MultipartFormData.parse_form_url_encoded
        )?

    message =
        Dict.get(dict, "message")?

    Stdout.line!("Decoded message: ${message}")?

    expected = "This + is a plus"
    Stdout.line!("Expected message: ${expected}")?

    if message == expected then
        Stdout.line!("Message decoded as expected.")?
        Ok({})
    else
        Stdout.line!("Message decoded incorrectly.")?

        Err(StrErr("Decoded message mismatch: expected '${expected}' but got '${message}'."))

respond! : Request, Model => Result Response _
respond! = |_, _|
    Ok(
        {
            status: 404,
            headers: [],
            body: [],
        },
    )
