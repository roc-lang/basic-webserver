module [
    splitOnList,
]

## Splits a list into sublists using a given list as seperator.
##
## Example:
## ```roc
## input = [1,2,3,4,5,6,7,3,4,0,0]
## actual = splitOnList input [3,4]
## expected = [[1,2], [5,6,7], [0, 0]]
## ```
##
splitOnList : List a, List a -> List (List a) where a implements Eq
splitOnList = \inputList, seperator ->

    # reserve capacity for markers which mark split boundaries
    initMarkers = List.withCapacity 100

    # find all the start and stop markers
    markers = List.walkWithIndex inputList initMarkers (walkHelpFindStarts inputList seperator)

    # split the input based on the markers
    walkSplitHelp inputList markers

# produces a Stop, followed by a sequence of Start, Stop, Start, Stop, ...
walkHelpFindStarts = \inputList, seperatorList ->
    if inputList == [] || seperatorList == [] then
        \_, _, _ -> []
    else
        \allMarkers, _, idx ->

            len = List.len seperatorList

            if List.sublist inputList { start: idx, len } == seperatorList then
                allMarkers
                |> List.append (Stop idx)
                |> List.append (Start (idx + len))
            else
                allMarkers

# empty input
expect
    input = []
    seperator = [1,2,3]
    help = walkHelpFindStarts input seperator
    actual = List.walkWithIndex input [] help
    expected = []
    actual == expected

# empty seperator
expect
    input = [1,2,3]
    seperator = []
    help = walkHelpFindStarts input seperator
    actual = List.walkWithIndex input [] help
    expected = []
    actual == expected

# seperator at start
expect
    input = [3,4,5,6,7,8]
    seperator = [3,4,5]
    help = walkHelpFindStarts input seperator
    actual = List.walkWithIndex input [] help
    expected = [Stop 0, Start 3]
    actual == expected

# multiple seperators in the middle
expect
    input = [1,2,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10]
    seperator = [3,4,5]
    help = walkHelpFindStarts input seperator
    actual = List.walkWithIndex input [] help
    expected = [Stop 2, Start 5, Stop 10, Start 13]
    actual == expected

# seperator at end
expect
    input = [6,7,8,3,4,5]
    seperator = [3,4,5]
    help = walkHelpFindStarts input seperator
    actual = List.walkWithIndex input [] help
    expected = [Stop 3, Start 6]
    actual == expected

walkSplitHelp : List a, List [Start U64, Stop U64] -> List (List a) where a implements Eq
walkSplitHelp = \input, markers ->
    go = \remainingMarkers, state ->
        when remainingMarkers is

                [] -> state

                [Stop stop, .. as rest] if stop == 0 -> go rest state

                [Stop stop, .. as rest] ->
                    go rest (List.append state (List.sublist input {start: 0, len: stop}))

                [Start start, Stop stop, .. as rest] ->
                    go rest (List.append state (List.sublist input {start, len: stop - start}))

                [Start start] if start >= List.len input -> state

                [Start start] ->
                    List.append state (List.sublist input {start, len: ((List.len input) - start)})

                _ -> crash "Unreachable:\n\tThis list should have matched earlier when branches: $(Inspect.toStr remainingMarkers)"

    go markers []

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
    input = [1,2,3,4,5,6,7,3,4,0,0]
    actual = splitOnList input [3,4]
    expected = [[1,2], [5,6,7], [0, 0]]
    actual == expected

expect
    input = [1,2,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10]
    actual = splitOnList input [3,4,5]
    expected = [[1,2], [6,7,8,9,10], [6,7,8,9,10]]
    actual == expected

expect
    input = [One, Two, Three, Four, Five, Six, Seven, Eight, One, Two, Nine, Ten, Three, Four, Five, Six, Seven, One, Two, Eight, Nine, Ten]
    actual = splitOnList input [One, Two]
    expected = [[Three, Four, Five, Six, Seven, Eight], [Nine, Ten, Three, Four, Five, Six, Seven], [Eight, Nine, Ten]]
    actual == expected

expect
    input =  [6,7,8,3,4,5]
    actual = splitOnList input [3,4,5]
    expected = [[6,7,8]]
    actual == expected

expect
    input = [3,4,5,6,7,8]
    actual = splitOnList input [3,4,5]
    expected = [[6,7,8]]
    actual == expected
