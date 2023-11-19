app "env"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Task.{ Task },
        pf.Http.{ Request, Response },
        pf.Env,
    ]
    provides [main] to pf

main : Request -> Task Response []
main = \_ ->

    # Check if DEBUG environment variable is set
    maybeDebug <- Env.var "DEBUG" |> Task.attempt

    debug = 
        when maybeDebug is 
            Ok var if !(Str.isEmpty var)  -> Bool.true
            _ -> Bool.false

    if debug then 
        # Respond with all the current environment variables
        vars <- Env.list |> Task.await

        body = 
            vars
            |> List.map (\(k, v) -> "\(k): \(v)")
            |> Str.joinWith "\n"
            |> Str.concat "\n"
            |> Str.toUtf8

        Task.ok { status: 200, headers: [], body }

    else 
        # Respond with a message that DEBUG is not set
        Task.ok { status: 200, headers: [], body: Str.toUtf8 "DEBUG var not set\n" }

   

    
