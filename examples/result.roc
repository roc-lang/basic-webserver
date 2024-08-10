app [Model, server] { pf: platform "../platform/main.roc" }

import pf.Task exposing [Task]
import pf.Http exposing [Request, Response]

# This example demonstrates the use of `Task.result`.
# It transforms a task that can either succeed with `ok`, or fail with `err`, into
# a task that succeeds with `Result ok err`.

Model : {}

server = { init, respond }

init : Task Model [Exit I32 Str]_
init = Task.ok {}

respond : Request, Model -> Task Response [ServerErr Str]_
respond = \_, _ ->
    when checkFile "good" |> Task.result! is
        Ok Good -> Task.ok { status: 200, headers: [], body: Str.toUtf8 "GOOD" }
        Ok Bad -> Task.ok { status: 200, headers: [], body: Str.toUtf8 "BAD" }
        Err IOError -> Task.ok { status: 500, headers: [], body: Str.toUtf8 "ERROR: IoError when executing checkFile." }

checkFile : Str -> Task [Good, Bad] [IOError]
checkFile = \str ->
    if str == "good" then
        Task.ok Good
    else if str == "bad" then
        Task.ok Bad
    else
        Task.err IOError
