app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Http exposing [Request, Response]

Model : {}

init! : {} => Result Model []
init! = \{} -> Ok {}

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = \_, _ ->
    when check_file! "good" is
        Ok Good -> Ok { status: 200, headers: [], body: Str.toUtf8 "GOOD" }
        Ok Bad -> Ok { status: 200, headers: [], body: Str.toUtf8 "BAD" }
        Err IOError -> Ok { status: 500, headers: [], body: Str.toUtf8 "ERROR: IoError when executing checkFile!." }

# imagine this function does some IO operation
# and returns a Result, succeding with a tag either Good or Bad,
# or failing with an IOError
check_file! : Str => Result [Good, Bad] [IOError]
check_file! = \str ->
    if str == "good" then
        Ok Good
    else if str == "bad" then
        Ok Bad
    else
        Err IOError
