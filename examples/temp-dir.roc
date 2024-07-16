app [main] { pf: platform "../platform/main.roc" }

import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]
import pf.Path
import pf.Env

## Returns the default temp dir
##
## !! requires --linker=legacy
## for example: `roc build examples/temp-dir.roc --linker=legacy`

main : Request -> Task Response []
main = \_ ->

    tempDirStr = Path.display Env.tempDir!

    Task.ok { status: 200, headers: [], body: Str.toUtf8 "The temp dir path is $(tempDirStr)" }
