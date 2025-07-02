app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Http exposing [Request, Response]
import pf.Path
import pf.Env

# To run this example: check the README.md in this folder

## Returns the default temp dir
##
## !! requires --linker=legacy
## for example: `roc build examples/temp-dir.roc --linker=legacy`

Model : {}

init! : {} => Result Model []
init! = |{}|
    Ok({})

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |_, _|

    temp_dir_str = Path.display(Env.temp_dir!({}))

    Ok(
        {
            status: 200,
            headers: [],
            body: Str.to_utf8("The temp dir path is ${temp_dir_str}"),
        },
    )
