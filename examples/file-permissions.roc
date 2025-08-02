app [Model, init!, respond!] { 
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.File

Model : {}

init! : {} => Result Model _
init! = |{}|
    file = "LICENSE"

    is_executable = File.is_executable!(file)?

    is_readable = File.is_readable!(file)?

    is_writable = File.is_writable!(file)?

    Stdout.line!(
        """
        ${file} file permissions:
            Executable: ${Inspect.to_str(is_executable)}
            Readable: ${Inspect.to_str(is_readable)}
            Writable: ${Inspect.to_str(is_writable)}
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