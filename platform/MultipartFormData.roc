## See IETF RFC 7578 Returning Values from Forms: multipart/form-data
## https://datatracker.ietf.org/doc/html/rfc7578
module [
    FormData,
    parse,
]

import SplitList exposing [splitOnList]

FormData : {
    ## Content-Disposition response header
    ## Indicates if content expects to be displayed inline or as attachment.
    ##
    ## Example: `inline` or `attachment; filename="filename.jpg"`
    disposition : List U8,
    
    ## Content-Type header
    ## Original media type of the resource.
    ##
    ## Example: `multipart/form-data; boundary=ExampleBoundaryString`
    type : List U8,

    ## Content-Transfer-Encoding
    ## Specifies how the body is encoded.
    ##
    ## Example: `base64` or `binary`
    encoding : List U8,

    ## Acutal data that was entered in the form, in encoded form.
    data : List U8,
}

newline = ['\r', '\n']
doubledash = ['-', '-']

## Produces function that extracts the header value. 
##
## Example call:
## ```roc
## parseContentF {
##    upper: Str.toUtf8 "Content-Disposition:",
##    lower: Str.toUtf8 "content-disposition:",
## }
##
## input = Str.toUtf8 "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nSome text here..."
## actual = parseContentDispositionF input
## expected = Ok {
##    value: Str.toUtf8 " form-data; name=\"sometext\"",
##    rest: Str.toUtf8 "\r\nSome text here...",
## }
## ```
##
parseContentF : { upper: List U8, lower: List U8 } -> (List U8 -> Result { value : List U8, rest : List U8 } _)
parseContentF = \{ upper, lower } -> \bytes ->

        toSearchUpper = List.concat newline upper
        toSearchLower = List.concat newline lower
        searchLength = List.len toSearchUpper
        afterSearch = List.sublist bytes { start: searchLength, len: Num.maxU64 }

        if
            List.startsWith bytes toSearchUpper
            || List.startsWith bytes toSearchLower
        then
            nextLineStart <-
                afterSearch
                |> List.findFirstIndex \b -> b == '\r'
                |> Result.try

            Ok {
                value: List.sublist afterSearch { start: 0, len: nextLineStart },
                rest: List.sublist afterSearch { start: nextLineStart, len: Num.maxU64 },
            }
        else
            Err ExpectedContent

parseContentDispositionF = parseContentF {
    upper: Str.toUtf8 "Content-Disposition:",
    lower: Str.toUtf8 "content-disposition:",
}

expect
    input = Str.toUtf8 "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nSome text here..."
    actual = parseContentDispositionF input
    expected = Ok {
        value: Str.toUtf8 " form-data; name=\"sometext\"",
        rest: Str.toUtf8 "\r\nSome text here...",
    }

    actual == expected

parseContentTypeF = parseContentF {
    upper: Str.toUtf8 "Content-Type:",
    lower: Str.toUtf8 "content-type:",
}

expect
    input = Str.toUtf8 "\r\ncontent-type: multipart/mixed; boundary=abcde\r\nSome text here..."
    actual = parseContentTypeF input
    expected = Ok {
        value: Str.toUtf8 " multipart/mixed; boundary=abcde",
        rest: Str.toUtf8 "\r\nSome text here...",
    }

    actual == expected

parseContentTransferEncodingF = parseContentF {
    upper: Str.toUtf8 "Content-Transfer-Encoding:",
    lower: Str.toUtf8 "content-transfer-encoding:",
}

expect
    input = Str.toUtf8 "\r\nContent-Transfer-Encoding: binary\r\nSome text here..."
    actual = parseContentTransferEncodingF input
    expected = Ok {
        value: Str.toUtf8 " binary",
        rest: Str.toUtf8 "\r\nSome text here...",
    }

    actual == expected

## Parses all headers: Content-Disposition, Content-Type and Content-Transfer-Encoding.
parseAllHeaders : List U8 -> Result FormData _
parseAllHeaders = \bytes ->

    doubleNewlineLength = 4 # \r\n\r\n

    when parseContentDispositionF bytes is
        Err err -> Err (ExpectedContentDisposition bytes err)
        Ok { value: disposition, rest: first } ->
            when parseContentTypeF first is
                Err _ ->
                    Ok {
                        disposition,
                        type: [],
                        encoding: [],
                        data: List.dropFirst first doubleNewlineLength,
                    }

                Ok { value: type, rest: second } ->
                    when parseContentTransferEncodingF second is
                        Err _ ->
                            Ok {
                                disposition,
                                type,
                                encoding: [],
                                data: List.dropFirst second doubleNewlineLength,
                            }

                        Ok { value: encoding, rest } ->
                            Ok {
                                disposition,
                                type,
                                encoding,
                                data: List.dropFirst rest doubleNewlineLength,
                            }

expect
    header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\n\r\n<FILE CONTENTS>"
    actual = parseAllHeaders (Str.toUtf8 header)
    expected = Ok {
        disposition: Str.toUtf8 " form-data; name=\"sometext\"",
        type: Str.toUtf8 "",
        encoding: Str.toUtf8 "",
        data: Str.toUtf8 "<FILE CONTENTS>",
    }

    actual == expected

expect
    header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nContent-Type: multipart/mixed; boundary=abcde\r\n\r\n<FILE CONTENTS>"
    actual = parseAllHeaders (Str.toUtf8 header)
    expected = Ok {
        disposition: Str.toUtf8 " form-data; name=\"sometext\"",
        type: Str.toUtf8 " multipart/mixed; boundary=abcde",
        encoding: Str.toUtf8 "",
        data: Str.toUtf8 "<FILE CONTENTS>",
    }

    actual == expected

expect
    header = "\r\nContent-Disposition: form-data; name=\"sometext\"\r\nContent-Type: multipart/mixed; boundary=abcde\r\nContent-Transfer-Encoding: binary\r\n\r\n<FILE CONTENTS>"
    actual = parseAllHeaders (Str.toUtf8 header)
    expected = Ok {
        disposition: Str.toUtf8 " form-data; name=\"sometext\"",
        type: Str.toUtf8 " multipart/mixed; boundary=abcde",
        encoding: Str.toUtf8 " binary",
        data: Str.toUtf8 "<FILE CONTENTS>",
    }

    actual == expected

## Parses the body of a multipart/form-data request.
##
## Example body with boundary 12345:
## ```
## --12345
## Content-Disposition: form-data; name="sometext"
##
## some text that you wrote in your html form ...
## --12345--
## ```
parse :
    {
        body : List U8,
        ## Each part of the form is enclosed between two boundary markers.
        boundary : List U8, 
    }
    -> Result (List FormData) [ExpectedEnclosedByBoundary]
parse = \{ body, boundary } ->

    startMarker = List.join [doubledash, boundary]
    endMarker = List.join [newline, doubledash, boundary, doubledash, newline]
    boundaryWithPrefix = List.join [newline, doubledash, boundary]

    isEnclosedByBoundary =
        List.startsWith body startMarker
        && List.endsWith body endMarker

    if isEnclosedByBoundary then
        body
        |> List.dropFirst (List.len startMarker)
        |> splitOnList boundaryWithPrefix
        |> List.dropIf \part -> part == doubledash
        |> List.keepOks parseAllHeaders
        |> Ok
    else
        Err ExpectedEnclosedByBoundary

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
