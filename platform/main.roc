platform "webserver"
    requires {} { main : Request -> Task Response [] } # TODO change to U16 for status code
    exposes [
        Path,
        Header,
        Request,
        Arg,
        Dir,
        Env,
        File,
        FileMetadata,
        Http,
        Stderr,
        Stdin,
        Stdout,
        Task,
        Tcp,
        Url,
        Utc,
        Sleep,
        Command,
    ]
    packages {}
    imports [Task.{ Task }, Request.{ Request, Method }, Response.{ Response }, Header.{ Header }]
    provides [mainForHost]

mainForHost : List U8 -> Task (List U8) []
mainForHost = \bytes ->
    Task.ok (responseToBytes { status: 200, headers: [], body: Str.toUtf8 "test" })
    # TODO send the Request directly over from the host, once the ABI bug is fixed
    # Temporary format: {method}\n{url}\n{headers}\n\n{body}
    # when parseMethod bytes is
    #     Ok (method, afterMethod) ->
    #         when parseUrl afterMethod is
    #             Ok (url, afterUrl) -> # NOTE: we don't send the HTTP version over; we don't care
    #                 (headers, body) = parseHeadersHelp [] afterUrl

    #                 main { method, url, headers, body }
    #                 |> Task.map responseToBytes

    #             Err InvalidUrl -> malformed "Invalid URL"
    #             Err MissingUrl -> malformed "HTTP request is missing URL"

    #     Err EmptyRequest -> malformed "Empty HTTP request"
    #     Err InvalidMethod -> malformed "Unsupported HTTP method"

malformed : Str -> Task (List U8) []
malformed = \body ->
    { status: 400, headers: [], body: Str.toUtf8 body }
    |> responseToBytes
    |> Task.ok

responseToBytes : Response -> List U8
responseToBytes = \{ status, headers, body } ->
    # {status}\n{headers-separated-by-newlines}\n\n{body}
    withoutBody =
        status
        |> Num.toStr
        |> Str.toUtf8
        |> List.append '\n'
        |> addHeaderBytes headers

    if List.isEmpty body then
        withoutBody
    else
        withoutBody
        |> List.append '\n' # We already have a trailing '\n' so this makes a blank line
        |> List.concat body

addHeaderBytes : List U8, List Header -> List U8
addHeaderBytes = \bytes, headers ->
    when List.first headers is
        Ok header ->
            bytes
            |> List.concat (Str.toUtf8 header.name)
            |> List.append ':'
            |> List.concat header.value
            |> List.append '\n'

        Err ListWasEmpty -> bytes

parseUrl : List U8 -> Result (Str, List U8) [InvalidUrl, MissingUrl]
parseUrl = \bytes ->
    when List.splitFirst bytes '\n' is
        Ok { before: urlBytes, after: rest } ->
            when Str.fromUtf8 urlBytes is
                Ok urlStr -> Ok (urlStr, rest)
                Err _ -> Err InvalidUrl

        Err NotFound -> Err MissingUrl

parseHeadersHelp : List Header, List U8 -> (List Header, List U8)
parseHeadersHelp = \headers, bytes ->
    when List.splitFirst bytes '\n' is
        Ok { before: line, after: rest } ->
            when List.splitFirst line ':' is
                Ok { before: nameBytes, after: value } ->
                    when Str.fromUtf8 nameBytes is
                        Ok name ->
                            # Add the header we just parsed and continue
                            headers
                            |> List.append { name, value }
                            |> parseHeadersHelp rest

                        Err _ ->
                            crash "TODO invalid header - bad UTF-8"

                Err NotFound ->
                    if List.isEmpty line then
                        # We hit a blank line, so we're done with headers! The rest is the body.
                        (headers, rest)
                    else
                        crash "TODO invalid header - missing :"

        Err NotFound ->
            # There are no more lines after the last header, so this request has no body!
            (headers, [])


parseMethod : List U8 -> Result (Method, List U8) [InvalidMethod, EmptyRequest]
parseMethod = \bytes ->
    when List.splitFirst bytes '\n' is
        Ok { before: ['G', 'E', 'T'], after: rest } -> Ok (GET, rest)
        Ok { before: ['P', 'O', 'S', 'T'], after: rest } -> Ok (POST, rest)
        Ok { before: ['P', 'U', 'T'], after: rest } -> Ok (PUT, rest)
        Ok { before: ['D', 'E', 'L', 'E', 'T', 'E'], after: rest } -> Ok (DELETE, rest)
        Ok { before: ['H', 'E', 'A', 'D'], after: rest } -> Ok (HEAD, rest)
        Ok { before: ['O', 'P', 'T', 'I', 'O', 'N', 'S'], after: rest } -> Ok (OPTIONS, rest)
        Ok _ -> Err InvalidMethod
        Err NotFound -> Err EmptyRequest
