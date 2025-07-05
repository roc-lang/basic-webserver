app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Sleep

# To run this example: check the README.md in this folder

Model : {}

init! : {} => Result Model []
init! = |{}| Ok({})

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |_, _|
    # Let the user know we're sleeping
    Stdout.line!("Sleeping for 1 second...")?

    # Sleep for 1 second
    Sleep.millis!(1000)

    Ok(
        {
            status: 200,
            headers: [],
            body: Str.to_utf8("Response delayed by 1 second"),
        },
    )