
app [Model, init!, respond!] { 
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.File
import pf.Utc

Model : {}

init! : {} => Result Model _
init! = |{}|
    file = "LICENSE"

    # NOTE: these functions will not work if basic-webserver was built with musl, which is the case for the normal tar.br URL release.
    # See https://github.com/roc-lang/basic-webserver?tab=readme-ov-file#developing--building-locally to build basic-webserver without musl.

    time_modified = Utc.to_iso_8601(File.time_modified!(file)?)

    time_accessed = Utc.to_iso_8601(File.time_accessed!(file)?)

    time_created = Utc.to_iso_8601(File.time_created!(file)?)


    Stdout.line!(
        """
        ${file} file time metadata:
            Modified: ${time_modified}
            Accessed: ${time_accessed}
            Created: ${time_created}
        """
    )?

    Ok({})

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |_, _|

    Ok(
        {
            status: 200,
            headers: [],
            body: Str.to_utf8("See example in init! function."),
        },
    )
