SplitList :: [].{
    ## Splits a list into sublists using a given list as separator.
    ##
    ## Example:
    ## ```roc
    ## input = [1,2,3,4,5,6,7,3,4,0,0]
    ## actual = split_on_list(input, [3,4])
    ## expected = [[1,2], [5,6,7], [0, 0]]
    ## ```
    ##
    split_on_list = |input_list, separator| {
        # find all the start and stop markers
        markers = List.fold_with_index(input_list, [], walk_help_find_starts(input_list, separator))

        # split the input based on the markers
        walk_split_help(input_list, markers)
    }

    # produces a Stop, followed by a sequence of Start, Stop, Start, Stop, ...
    walk_help_find_starts = |input_list, separator_list|
        if input_list == [] or separator_list == [] {
            |_, _, _| []
        } else {
            |all_markers, _, idx| {
                len = List.len(separator_list)

                if List.sublist(input_list, { start: idx, len: len }) == separator_list {
                    all_markers
                        .append(Stop(idx))
                        .append(Start(idx + len))
                } else {
                    all_markers
                }
            }
        }

    walk_split_help = |input, markers| {
        go = |remaining_markers, state|
            match remaining_markers {
                [] => state
                [Stop(stop), .. as rest] if stop == 0 => go(rest, state)
                [Stop(stop), .. as rest] =>
                    go(rest, state.append(List.sublist(input, { start: 0, len: stop })))

                [Start(start), Stop(stop), .. as rest] =>
                    go(rest, state.append(List.sublist(input, { start: start, len: stop - start })))

                [Start(start)] if start >= List.len(input) => state
                [Start(start)] =>
                    state.append(List.sublist(input, { start: start, len: List.len(input) - start }))

                _ => {
                    crash "Unreachable:\n\tThis list should have matched earlier when branches: ${Str.inspect(remaining_markers)}"
                }
            }

        go(markers, [])
    }
}

# empty input
expect {
    input = []
    separator = [1, 2, 3]
    help = SplitList.walk_help_find_starts(input, separator)
    actual = List.fold_with_index(input, [], help)
    expected = []
    actual == expected
}

# empty separator
expect {
    input = [1, 2, 3]
    separator = []
    help = SplitList.walk_help_find_starts(input, separator)
    actual = List.fold_with_index(input, [], help)
    expected = []
    actual == expected
}

# separator at start
expect {
    input = [3, 4, 5, 6, 7, 8]
    separator = [3, 4, 5]
    help = SplitList.walk_help_find_starts(input, separator)
    actual = List.fold_with_index(input, [], help)
    expected = [Stop(0), Start(3)]
    actual == expected
}

# multiple separators in the middle
expect {
    input = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 3, 4, 5, 6, 7, 8, 9, 10]
    separator = [3, 4, 5]
    help = SplitList.walk_help_find_starts(input, separator)
    actual = List.fold_with_index(input, [], help)
    expected = [Stop(2), Start(5), Stop(10), Start(13)]
    actual == expected
}

# separator at end
expect {
    input = [6, 7, 8, 3, 4, 5]
    separator = [3, 4, 5]
    help = SplitList.walk_help_find_starts(input, separator)
    actual = List.fold_with_index(input, [], help)
    expected = [Stop(3), Start(6)]
    actual == expected
}

expect {
    actual = SplitList.walk_split_help([1, 2, 3, 5, 6, 7, 8, 9, 10], [Stop(2)])
    expected = [[1, 2]]
    actual == expected
}

expect {
    input = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 3, 4, 5, 6, 7, 8, 9, 10]
    actual = SplitList.walk_split_help(input, [Stop(2), Start(5), Stop(10), Start(13)])
    expected = [[1, 2], [6, 7, 8, 9, 10], [6, 7, 8, 9, 10]]
    actual == expected
}

expect {
    input = [1, 2, 3, 4, 5, 6, 7, 3, 4, 0, 0]
    actual = SplitList.split_on_list(input, [3, 4])
    expected = [[1, 2], [5, 6, 7], [0, 0]]
    actual == expected
}

expect {
    input = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 3, 4, 5, 6, 7, 8, 9, 10]
    actual = SplitList.split_on_list(input, [3, 4, 5])
    expected = [[1, 2], [6, 7, 8, 9, 10], [6, 7, 8, 9, 10]]
    actual == expected
}

expect {
    input = [One, Two, Three, Four, Five, Six, Seven, Eight, One, Two, Nine, Ten, Three, Four, Five, Six, Seven, One, Two, Eight, Nine, Ten]
    actual = SplitList.split_on_list(input, [One, Two])
    expected = [[Three, Four, Five, Six, Seven, Eight], [Nine, Ten, Three, Four, Five, Six, Seven], [Eight, Nine, Ten]]
    actual == expected
}

expect {
    input = [6, 7, 8, 3, 4, 5]
    actual = SplitList.split_on_list(input, [3, 4, 5])
    expected = [[6, 7, 8]]
    actual == expected
}

expect {
    input = [3, 4, 5, 6, 7, 8]
    actual = SplitList.split_on_list(input, [3, 4, 5])
    expected = [[6, 7, 8]]
    actual == expected
}
