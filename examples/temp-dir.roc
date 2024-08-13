app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Http exposing [Request, Response]
import pf.Path
import pf.Env

## Returns the default temp dir
##
## !! requires --linker=legacy
## for example: `roc build examples/temp-dir.roc --linker=legacy`

Model : {}

server = { init: Task.ok {}, respond }

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->
    tempDirStr = Path.display Env.tempDir!

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "The temp dir path is $(tempDirStr)" }
