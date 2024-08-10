app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Path
import pf.Env

## Returns the default temp dir
##
## !! requires --linker=legacy
## for example: `roc build examples/temp-dir.roc --linker=legacy`

Model : {}

server = { init, respond }

init : Task Model [Exit I32 Str]_
init = Task.ok {}

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->
    tempDirStr = Path.display Env.tempDir!

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "The temp dir path is $(tempDirStr)" }
