app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.File
import pf.Path
import pf.Server
import http.Response

# To run this example: check the root README.md

Model : ReadSummary
Action : [GetSummary]
Result : [Summary(ReadSummary)]

ReadSummary : {
    lines_read : U64,
    bytes_read : U64,
}

program = { init!, transition, respond!, shutdown! }

init! : () => Try({ config : Server.Config, model : Model }, [Exit(I64), ..])
init! = || {
    reader = File.open_reader!(Path.utf8("LICENSE")) ? |_| Exit(1)
    summary = process_line!(reader, { lines_read: 0, bytes_read: 0 }) ? |_| Exit(1)

    Ok({ config: Server.default_config, model: summary })
}

transition : Action, Model -> { model : Model, result : Result }
transition = |GetSummary, model| { model, result: Summary(model) }

respond! : Server.Request, Server.State(Action, Result) => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_, state| {
    Summary(model) = state.apply!(GetSummary) ? |_| ServerErr("Server is stopping")
    Ok(
        Server.respond(Response.from_status(200).with_body(
            Str.to_utf8("{bytes_read: ${model.bytes_read.to_str()}, lines_read: ${model.lines_read.to_str()}}"),
        )),
    )
}

shutdown! : Server.ShutdownReason, Model => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})

## Count the number of lines and bytes read.
process_line! : File.Reader, ReadSummary => Try(ReadSummary, _)
process_line! = |reader, { lines_read, bytes_read }|
    match reader.read_line!() {
        Ok(bytes) if bytes.len() == 0 =>
            Ok({ lines_read, bytes_read })

        Ok(bytes) =>
            process_line!(
                reader,
                {
                    lines_read: lines_read + 1,
                    bytes_read: bytes_read + bytes.len(),
                },
            )

        Err(err) => Err(err)
    }
