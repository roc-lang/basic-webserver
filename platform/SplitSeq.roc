module [
    splitOnSeq,
]

## Splits a list into sublists around on a given sequence of elements.
splitOnSeq : List a, List a -> List (List a) where a implements Eq
splitOnSeq = \input, needle ->

    # reserve capacity for tokens which mark sublist boundaries
    init = List.withCapacity 100

    # find all the starts and stops
    tokens = List.walkWithIndex input init (walkHelpFindStarts input needle)

    # split the input based on the tokens
    walkSplitHelp input tokens

# produces a Stop, followed by a sequence of Start, Stop, Start, Stop, ...
walkHelpFindStarts = \input, needle ->
    if input == [] || needle == [] then
        \_, _, _ -> []
    else
        \state, _, idx ->

            len = List.len needle

            if List.sublist input { start: idx, len } == needle then
                state
                |> List.append (Stop idx)
                |> List.append (Start (idx + len))
            else
                state

# no input
expect
    input = []
    needle = [1,2,3]
    help = walkHelpFindStarts input needle
    actual = List.walkWithIndex input [] help
    expected = []
    actual == expected

# no needle
expect
    input = [1,2,3]
    needle = []
    help = walkHelpFindStarts input needle
    actual = List.walkWithIndex input [] help
    expected = []
    actual == expected

# needle at start
expect
    input = [3,4,5,6,7,8]
    needle = [3,4,5]
    help = walkHelpFindStarts input needle
    actual = List.walkWithIndex input [] help
    expected = [Stop 0, Start 3]
    actual == expected

# multiple needles in the middle
expect
    input = [1,2,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10]
    needle = [3,4,5]
    help = walkHelpFindStarts input needle
    actual = List.walkWithIndex input [] help
    expected = [Stop 2, Start 5, Stop 10, Start 13]
    actual == expected

# needle at end
expect
    input = [6,7,8,3,4,5]
    needle = [3,4,5]
    help = walkHelpFindStarts input needle
    actual = List.walkWithIndex input [] help
    expected = [Stop 3, Start 6]
    actual == expected

walkSplitHelp : List a, List [Start U64, Stop U64] -> List (List a) where a implements Eq
walkSplitHelp = \input, tokens ->
    go = \remainingTokens, acc ->
        when remainingTokens is

                [] -> acc

                [Stop stop, .. as rest] if stop == 0 -> go rest acc

                [Stop stop, .. as rest] ->
                    go rest (List.append acc (List.sublist input {start: 0, len: stop}))

                [Start start, Stop stop, .. as rest] ->
                    go rest (List.append acc (List.sublist input {start, len: stop - start}))

                [Start start] if start >= List.len input -> acc

                [Start start] ->
                    List.append acc (List.sublist input {start, len: ((List.len input) - start)})

                # should have matched Start and Stop pairs
                _ -> crash "unreachable $(Inspect.toStr remainingTokens)"

    go tokens []

expect
    actual = walkSplitHelp [1,2,3,5,6,7,8,9,10] [Stop 2]
    expected = [[1,2]]
    actual == expected

expect
    input = [1,2,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10]
    actual = walkSplitHelp input [Stop 2, Start 5, Stop 10, Start 13]
    expected = [[1,2], [6,7,8,9,10], [6,7,8,9,10]]
    actual == expected

expect
    input = [1,2,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10]
    actual = splitOnSeq input [3,4,5]
    expected = [[1,2], [6,7,8,9,10], [6,7,8,9,10]]
    actual == expected

expect
    input = [One, Two, Three, Four, Five, Six, Seven, Eight, One, Two, Nine, Ten, Three, Four, Five, Six, Seven, One, Two, Eight, Nine, Ten]
    actual = splitOnSeq input [One, Two]
    expected = [[Three, Four, Five, Six, Seven, Eight], [Nine, Ten, Three, Four, Five, Six, Seven], [Eight, Nine, Ten]]
    actual == expected

expect
    input =  [6,7,8,3,4,5]
    actual = splitOnSeq input [3,4,5]
    expected = [[6,7,8]]
    actual == expected

expect
    input = [3,4,5,6,7,8]
    actual = splitOnSeq input [3,4,5]
    expected = [[6,7,8]]
    actual == expected
