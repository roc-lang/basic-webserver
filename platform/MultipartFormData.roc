## See IETF RFC 7578 Returning Values from Forms: multipart/form-data
## https://datatracker.ietf.org/doc/html/rfc7578
module [
    FormData,
    parse,
]

import SplitSeq exposing [splitOnSeq]

FormData : {
    disposition : List U8,
    type : List U8,
    encoding : List U8,
    data : List U8,
}

newline = ['\r', '\n']
doubledash = ['-', '-']

# parse each header individually - Content-Disposition, Content-Type, Content-Transfer-Encoding
parseContent : _ -> (List U8 -> Result { val : List U8, rest : List U8 } _)
parseContent = \{ upper, lower } -> \bytes ->

        searchUpper = List.concat newline upper
        searchLower = List.concat newline lower
        searchLength = List.len searchUpper
        listWithoutSearch = List.sublist bytes { start: searchLength, len: Num.maxU64 }

        if
            List.startsWith bytes searchUpper
            || List.startsWith bytes searchLower
        then
            nextLineStart <-
                listWithoutSearch
                |> List.findFirstIndex \b -> b == '\r'
                |> Result.try

            Ok {
                val: List.sublist listWithoutSearch { start: 0, len: nextLineStart },
                rest: List.sublist listWithoutSearch { start: nextLineStart, len: Num.maxU64 },
            }
        else
            Err ExpectedContent

parseContentDisposition = parseContent {
    upper: Str.toUtf8 "Content-Disposition:",
    lower: Str.toUtf8 "content-disposition:",
}

expect
    input = Str.toUtf8 "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nSome text here..."
    actual = parseContentDisposition input
    expected = Ok {
        val: Str.toUtf8 " form-data; name=\"sometext\"",
        rest: Str.toUtf8 "\r\nSome text here...",
    }

    actual == expected

parseContentType = parseContent {
    upper: Str.toUtf8 "Content-Type:",
    lower: Str.toUtf8 "content-type:",
}

expect
    input = Str.toUtf8 "\r\ncontent-type: multipart/mixed; boundary=abcde\r\nSome text here..."
    actual = parseContentType input
    expected = Ok {
        val: Str.toUtf8 " multipart/mixed; boundary=abcde",
        rest: Str.toUtf8 "\r\nSome text here...",
    }

    actual == expected

parseContentTransferEncoding = parseContent {
    upper: Str.toUtf8 "Content-Transfer-Encoding:",
    lower: Str.toUtf8 "content-transfer-encoding:",
}

expect
    input = Str.toUtf8 "\r\nContent-Transfer-Encoding: binary\r\nSome text here..."
    actual = parseContentTransferEncoding input
    expected = Ok {
        val: Str.toUtf8 " binary",
        rest: Str.toUtf8 "\r\nSome text here...",
    }

    actual == expected

# parse headers combined
parseHeaders : List U8 -> Result FormData _
parseHeaders = \bytes ->

    doubleNewlineLength = 4 # \r\n\r\n

    when parseContentDisposition bytes is
        Err err -> Err (ExpectedContentDisposition bytes err)
        Ok { val: disposition, rest: first } ->
            when parseContentType first is
                Err _ ->
                    Ok {
                        disposition,
                        type: [],
                        encoding: [],
                        data: List.dropFirst first doubleNewlineLength,
                    }

                Ok { val: type, rest: second } ->
                    when parseContentTransferEncoding second is
                        Err _ ->
                            Ok {
                                disposition,
                                type,
                                encoding: [],
                                data: List.dropFirst second doubleNewlineLength,
                            }

                        Ok { val: encoding, rest } ->
                            Ok {
                                disposition,
                                type,
                                encoding,
                                data: List.dropFirst rest doubleNewlineLength,
                            }

expect
    input = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\n\r\n<FILE CONTENTS>"
    actual = parseHeaders (Str.toUtf8 input)
    expected = Ok {
        disposition: Str.toUtf8 " form-data; name=\"sometext\"",
        type: Str.toUtf8 "",
        encoding: Str.toUtf8 "",
        data: Str.toUtf8 "<FILE CONTENTS>",
    }

    actual == expected

expect
    input = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nContent-Type: multipart/mixed; boundary=abcde\r\n\r\n<FILE CONTENTS>"
    actual = parseHeaders (Str.toUtf8 input)
    expected = Ok {
        disposition: Str.toUtf8 " form-data; name=\"sometext\"",
        type: Str.toUtf8 " multipart/mixed; boundary=abcde",
        encoding: Str.toUtf8 "",
        data: Str.toUtf8 "<FILE CONTENTS>",
    }

    actual == expected

expect
    input = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nContent-Type: multipart/mixed; boundary=abcde\r\nContent-Transfer-Encoding: binary\r\n\r\n<FILE CONTENTS>"
    actual = parseHeaders (Str.toUtf8 input)
    expected = Ok {
        disposition: Str.toUtf8 " form-data; name=\"sometext\"",
        type: Str.toUtf8 " multipart/mixed; boundary=abcde",
        encoding: Str.toUtf8 " binary",
        data: Str.toUtf8 "<FILE CONTENTS>",
    }

    actual == expected

## Parses the body of a multipart/form-data request
##
## ```
## Content-Type: multipart/form-data; boundary=12345
##
## --12345
## Content-Disposition: form-data; name="sometext"
##
## some text that you wrote in your html form ...
## --12345--
## ```
parse :
    {
        body : List U8,
        boundary : List U8,
    }
    -> Result (List FormData) _ # [InvalidMultipartFormData]
parse = \{ body, boundary } ->

    start = List.join [doubledash, boundary]
    end = List.join [newline, doubledash, boundary, doubledash, newline]
    boundaryWithPrefix = List.join [newline, doubledash, boundary]

    isFencedByBoundary =
        List.startsWith body start
        && List.endsWith body end

    if isFencedByBoundary then
        body
        |> List.dropFirst (List.len start)
        |> splitOnSeq boundaryWithPrefix
        |> List.dropIf \part -> part == doubledash
        |> List.keepOks parseHeaders
        |> Ok
    else
        Err ExpectedFendedByBoundary

expect
    # """
    # ------WebKitFormBoundaryQGx5ri4XFwWbaAX4
    # Content-Disposition: form-data; name="file"; filename="sample2.csv"
    # Content-Type: text/csv
    #
    # First,Last
    # Rachel,Booker
    #
    # ------WebKitFormBoundaryQGx5ri4XFwWbaAX4--
    #
    # """
    actual = parse {
        body: [45, 45, 45, 45, 45, 45, 87, 101, 98, 75, 105, 116, 70, 111, 114, 109, 66, 111, 117, 110, 100, 97, 114, 121, 70, 71, 54, 83, 65, 109, 121, 106, 112, 49, 108, 118, 102, 57, 80, 55, 13, 10, 67, 111, 110, 116, 101, 110, 116, 45, 68, 105, 115, 112, 111, 115, 105, 116, 105, 111, 110, 58, 32, 102, 111, 114, 109, 45, 100, 97, 116, 97, 59, 32, 110, 97, 109, 101, 61, 34, 102, 105, 108, 101, 34, 59, 32, 102, 105, 108, 101, 110, 97, 109, 101, 61, 34, 115, 97, 109, 112, 108, 101, 50, 46, 99, 115, 118, 34, 13, 10, 67, 111, 110, 116, 101, 110, 116, 45, 84, 121, 112, 101, 58, 32, 116, 101, 120, 116, 47, 99, 115, 118, 13, 10, 13, 10, 70, 105, 114, 115, 116, 44, 76, 97, 115, 116, 13, 10, 82, 97, 99, 104, 101, 108, 44, 66, 111, 111, 107, 101, 114, 13, 10, 13, 10, 45, 45, 45, 45, 45, 45, 87, 101, 98, 75, 105, 116, 70, 111, 114, 109, 66, 111, 117, 110, 100, 97, 114, 121, 70, 71, 54, 83, 65, 109, 121, 106, 112, 49, 108, 118, 102, 57, 80, 55, 45, 45, 13, 10],
        boundary: [45, 45, 45, 45, 87, 101, 98, 75, 105, 116, 70, 111, 114, 109, 66, 111, 117, 110, 100, 97, 114, 121, 70, 71, 54, 83, 65, 109, 121, 106, 112, 49, 108, 118, 102, 57, 80, 55],
    }
    # Result.isErr actual
    expected = Ok [
        {
            data: [70, 105, 114, 115, 116, 44, 76, 97, 115, 116, 13, 10, 82, 97, 99, 104, 101, 108, 44, 66, 111, 111, 107, 101, 114, 13, 10],
            disposition: [32, 102, 111, 114, 109, 45, 100, 97, 116, 97, 59, 32, 110, 97, 109, 101, 61, 34, 102, 105, 108, 101, 34, 59, 32, 102, 105, 108, 101, 110, 97, 109, 101, 61, 34, 115, 97, 109, 112, 108, 101, 50, 46, 99, 115, 118, 34],
            encoding: [],
            type: [32, 116, 101, 120, 116, 47, 99, 115, 118],
        },
    ]

    actual == expected

expect
    input = Str.toUtf8 "--12345\r\nContent-Disposition: form-data; name=\"sometext\"\r\n\r\nsome text sent via post...\r\n--12345--\r\n"
    actual = parse {
        body: input,
        boundary: Str.toUtf8 "12345",
    }
    expected = Ok [
        {
            disposition: Str.toUtf8 " form-data; name=\"sometext\"",
            type: [],
            encoding: [],
            data: Str.toUtf8 "some text sent via post...",
        },
    ]

    actual == expected

expect
    body = Str.toUtf8 "--AaB03x\r\nContent-Disposition: form-data; name=\"submit-name\"\r\n\r\nLarry\r\n--AaB03x\r\nContent-Disposition: form-data; name=\"files\"\r\nContent-Type: multipart/mixed; boundary=BbC04y\r\n\r\n--BbC04y\r\nContent-Disposition: file; filename=\"file1.txt\"\r\nContent-Type: text/plain\r\n\r\n... contents of file1.txt ...\r\n--BbC04y\r\nContent-Disposition: file; filename=\"file2.gif\"\r\nContent-Type: image/gif\r\nContent-Transfer-Encoding: binary\r\n\r\n...contents of file2.gif...\r\n--BbC04y--\r\n--AaB03x--\r\n"
    boundary = Str.toUtf8 "AaB03x"
    actual = parse { body, boundary }
    expected = Ok [
        {
            disposition: Str.toUtf8 " form-data; name=\"submit-name\"",
            type: [],
            encoding: [],
            data: Str.toUtf8 "Larry",
        },
        {
            disposition: Str.toUtf8 " form-data; name=\"files\"",
            type: Str.toUtf8 " multipart/mixed; boundary=BbC04y",
            encoding: [],
            data: Str.toUtf8 "--BbC04y\r\nContent-Disposition: file; filename=\"file1.txt\"\r\nContent-Type: text/plain\r\n\r\n... contents of file1.txt ...\r\n--BbC04y\r\nContent-Disposition: file; filename=\"file2.gif\"\r\nContent-Type: image/gif\r\nContent-Transfer-Encoding: binary\r\n\r\n...contents of file2.gif...\r\n--BbC04y--",
        },
    ]

    actual == expected
