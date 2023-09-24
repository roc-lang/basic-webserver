app "app"
    packages { pf: "../platform/main.roc" }
    imports [pf.Task.{ Task }, pf.Request.{ Request }, pf.Url, pf.Response.{ Response }]
    provides [main] to pf

main : Request -> Task Response []
main = \req ->
    url = Url.fromStr req.url
    path = Url.path url

    # dbg url

    if path |> Str.startsWith "/foo/bar" then
        # validateToken url
        Task.ok { status: 200, headers: [], body: "Found: \(path)" |> Str.toUtf8 }
    else
        # TODO return HTTP 404
        Task.ok { status: 404, headers: [], body: "Not Found: \(path)" |> Str.toUtf8 }

# validateToken : Url -> Task Str []
# validateToken = \_url ->
#     # params = Url.queryParams url

#     task =
#         clientSecret <-
#             Env.var "SECRET"
#             |> Task.mapErr \VarNotFound -> MissingSecretId
#             |> Task.await

#         # dbg clientSecret

#         # TODO causes some sort of signal, e.g. segfault, on repeated requests
#         # clientId <-
#         #     Dict.get params "clientId"
#         #     |> Result.mapErr \KeyNotFound -> MissingClientId
#         #     |> Task.awaitResult

#         {
#             method: Get,
#             headers: [],
#             # url: "\(baseUrl)/introspect",
#             url: "http://example.com",
#             body: Http.emptyBody,
#             timeout: NoTimeout,
#         }
#         |> Http.send
#         # |> Task.mapErr \err ->
#         #     dbg clientSecret
#         #     dbg err
#         #     err

#     result <- Task.attempt task

#     when result is
#         Ok responseBody -> Task.ok "all done: \(responseBody)"
#         Err MissingSecretId -> Task.ok "SECRET not found in env vars"
#         Err MissingClientId -> Task.ok "clientId not found in query param"
#         Err err ->
#             dbg err
#             Task.ok "Oops, something went wrong with the HTTP request!"
