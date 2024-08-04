# Vendored from https://github.com/quelgar/roc-utils
#
# Thank you Lachlan O'Dea <https://github.com/quelgar>
#
# TODO: import from the package release when this issue is resolved
# https://github.com/roc-lang/roc/issues/6931
#
module [encode, decode]

base64IndexTable = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
    'i',
    'j',
    'k',
    'l',
    'm',
    'n',
    'o',
    'p',
    'q',
    'r',
    's',
    't',
    'u',
    'v',
    'w',
    'x',
    'y',
    'z',
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '+',
    '/',
]

reverseBase64IndexMap = base64IndexTable |> List.mapWithIndex (\e, i -> (e, i)) |> Dict.fromList |> Dict.insert '=' 0

## Encodes a list of bytes into a Base64 string.
encode : List U8 -> Str
encode = \bytes ->
    length = List.len bytes
    paddingCount =
        when length % 3 is
            1 -> 2
            2 -> 1
            _ -> 0
    paddedInput = List.concat bytes (List.repeat 0 paddingCount)
    encodeChunk = \state, chunk ->
        when chunk is
            [a, b, c] ->
                n =
                    Num.toU32 a
                    |> Num.shiftLeftBy 16
                    |> Num.bitwiseOr (Num.toU32 b |> Num.shiftLeftBy 8)
                    |> Num.bitwiseOr (Num.toU32 c)
                six1 = Num.shiftRightZfBy n 18 |> Num.bitwiseAnd 0x3F
                six2 = Num.shiftRightZfBy n 12 |> Num.bitwiseAnd 0x3F
                six3 = Num.shiftRightZfBy n 6 |> Num.bitwiseAnd 0x3F
                six4 = n |> Num.bitwiseAnd 0x3F
                when List.mapTry [six1, six2, six3, six4] \i -> List.get base64IndexTable (Num.toU64 i) is
                    Ok l -> List.concat state l
                    Err _ -> crash "bug in base64Encode"

            other -> crash "expected a list of 3 elements, but got $(List.len other |> Num.toStr) elements"

    outPadding = List.repeat '=' paddingCount
    outLength = (length + paddingCount) // 3 * 4

    List.chunksOf paddedInput 3
    |> List.walk (List.withCapacity outLength) encodeChunk
    |> List.dropLast paddingCount
    |> List.concat outPadding
    |> Str.fromUtf8
    |> \r ->
        when r is
            Ok v -> v
            Err _ -> crash "bug in base64Encode"

expect
    result = Str.toUtf8 "Many hands make light work." |> encode
    result == "TWFueSBoYW5kcyBtYWtlIGxpZ2h0IHdvcmsu"

expect
    result = Str.toUtf8 "my country is the world, and my religion is to do good." |> encode
    result == "bXkgY291bnRyeSBpcyB0aGUgd29ybGQsIGFuZCBteSByZWxpZ2lvbiBpcyB0byBkbyBnb29kLg=="

expect
    result = [] |> encode
    result == ""

expect
    result = [0] |> encode
    result == "AA=="

expect
    result = [0, 0, 0] |> encode
    result == "AAAA"

decode : Str -> Result (List U8) [InvalidBase64Char, InvalidBase64Length]
decode = \str ->
    chars = str |> Str.toUtf8
    length = List.len chars
    if length % 4 != 0 then
        Err InvalidBase64Length
    else
        outLength = length // 4 * 3
        chars
        |> List.chunksOf 4
        |> List.walkTry (List.withCapacity outLength) \state, chunk4 ->
            paddingCount = List.countIf chunk4 \c -> c == '='
            chunk4
            |> List.mapTry \c -> Dict.get reverseBase64IndexMap c
            |> Result.map \l ->
                when l is
                    [six1, six2, six3, six4] ->
                        shifted1 = Num.shiftLeftBy six1 18
                        shifted2 = Num.shiftLeftBy six2 12
                        shifted3 = Num.shiftLeftBy six3 6
                        shifted4 = six4
                        combined = shifted1 |> Num.bitwiseOr shifted2 |> Num.bitwiseOr shifted3 |> Num.bitwiseOr shifted4
                        bytes =
                            [
                                Num.shiftRightZfBy combined 16 |> Num.toU8,
                                Num.shiftRightZfBy combined 8 |> Num.toU8,
                                combined |> Num.toU8,
                            ]
                            |> List.dropLast paddingCount
                        state |> List.concat bytes

                    _ -> crash "bug in base64Decode: should have already checked the length was a multiple of 4"
        |> Result.mapErr \_ -> InvalidBase64Char

expect
    result = decode "TWFueSBoYW5kcyBtYWtlIGxpZ2h0IHdvcmsu"
    result == Ok (Str.toUtf8 "Many hands make light work.")

expect
    result = decode "bXkgY291bnRyeSBpcyB0aGUgd29ybGQsIGFuZCBteSByZWxpZ2lvbiBpcyB0byBkbyBnb29kLg=="
    result == Ok (Str.toUtf8 "my country is the world, and my religion is to do good.")

expect
    result = decode ""
    result == Ok []

expect
    result = decode "AA=="
    result == Ok [0]

expect
    result = decode "AAAA"
    result == Ok [0, 0, 0]
