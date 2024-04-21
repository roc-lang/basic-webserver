app "result"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \_ ->
    when checkFile "good" |> Task.result! is
        Ok Good -> Task.ok { status: 200, headers: [], body: Str.toUtf8 "GOOD" }
        Ok Bad -> Task.ok { status: 200, headers: [], body: Str.toUtf8 "BAD" }
        Err IOError -> Task.ok { status: 200, headers: [], body: Str.toUtf8 "ERROR" }     

checkFile : Str -> Task [Good, Bad] [IOError]
checkFile = \str ->
    if str == "good" then 
        Task.ok Good 
    else if str == "bad" then 
        Task.ok Bad 
    else 
        Task.err IOError