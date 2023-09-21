platform "webserver"
    requires {} { main : Request -> Task Str [] } # TODO change to U16 for status code
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
    # TODO send the Request directly over from the host, once the ABI bug is fixed
    # Temporary format: {method}\n{url}\n{headers}\n\n{body}
    when parseMethod bytes is
        Ok (method, afterMethod) ->
            when parseUrl afterMethod is
                Ok (url, afterUrl) -> # NOTE: we don't send the HTTP version over; we don't care
                    (headers, body) = parseHeadersHelp [] afterUrl

                    main { method, url, headers, body }
                    |> Task.map responseToBytes

                Err InvalidUrl -> { status: 400, body: "Invalid URL" }
                Err MissingUrl -> { status: 400, body: "HTTP request is missing URL" }

        Err EmptyRequest -> responseToBytes { status: 400, body: "Empty HTTP request" }
        Err InvalidMethod -> responseToBytes { status: 400, body: "Unsupported HTTP method" }

responseToBytes : Response -> List U8

parseUrl : List U8 -> Result (Str, List U8) [InvalidUrl, MissingUrl]
parseUrl = \bytes ->
    when List.splitFirst bytes '\n' is
        Ok (urlBytes, rest) ->
            when Str.fromUtf8 urlBytes is
                Ok urlStr -> Ok (urlStr, rest)
                Err _ -> Err InvalidUrl

        Err ListWasEmpty -> Err MissingUrl

parseHeadersHelp : List Header, List U8 -> (List Header, List U8)
parseHeadersHelp = \headers, bytes ->
    when List.splitFirst bytes '\n' is
        Ok (line, rest) ->
            when List.splitFirst line ':' is
                Ok (name, value) ->
                    # Add the header we just parsed and continue
                    headers
                    |> List.append { name, value }
                    |> parseHeadersHelp rest

                Err ListWasEmpty ->
                    # We hit a blank line, so we're done with headers! The rest is the body.
                    (headers, rest)

        Err ListWasEmpty ->
            # There are no more lines after the last header, so this request has no body!
            (headers, [])


parseMethod : List U8 -> Result (Method, List U8) [InvalidMethod, EmptyRequest]
parseMethod = \bytes ->
    when List.splitFirst bytes '\n' is
        Ok (['G', 'E', 'T'], rest) -> Ok (GET, rest)
        Ok (['P', 'O', 'S', 'T'], rest) -> Ok (POST, rest)
        Ok (['P', 'U', 'T'], rest) -> Ok (PUT, rest)
        Ok (['D', 'E', 'L', 'E', 'T', 'E'], rest) -> Ok (DELETE, rest)
        Ok (['H', 'E', 'A', 'D'], rest) -> Ok (HEAD, rest)
        Ok (['O', 'P', 'T', 'I', 'O', 'N', 'S'], rest) -> Ok (OPTIONS, rest)
        Ok _ -> Err InvalidMethod
        Err ListWasEmpty -> Err EmptyRequest
