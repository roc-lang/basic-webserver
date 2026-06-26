## A [Uniform Resource Locator](https://en.wikipedia.org/wiki/URL).
##
## It could be an absolute address, such as `https://roc-lang.org/authors` or
## a relative address, such as `/authors`. You can create one using [Url.from_str].
Url := [Url(Str)].{
    ## Reserve the given number of bytes as extra capacity. This can avoid reallocation
    ## when calling multiple functions that increase the length of the URL.
    ##
    ## The following example reserves 50 bytes, then builds the url `https://example.com/stuff?caf%C3%A9=du%20Monde&email=hi%40example.com`;
    ## ```
    ## Url.from_str("https://example.com")
    ##     .reserve(50)
    ##     .append("stuff")
    ##     .append_param("café", "du Monde")
    ##     .append_param("email", "hi@example.com")
    ## ```
    ## The [Str.count_utf8_bytes](https://www.roc-lang.org/builtins/Str#count_utf8_bytes) function can be helpful in finding out how many bytes to reserve.
    ##
    ## There is no `Url.with_capacity` because it's better to reserve extra capacity
    ## on a [Str] first, and then pass that string to [Url.from_str]. This function will make use
    ## of the extra capacity.
    reserve : Url, U64 -> Url
    reserve = |Url(str), cap|
        Url(Str.reserve(str, cap))

    ## Create a [Url] without validating or [percent-encoding](https://en.wikipedia.org/wiki/Percent-encoding)
    ## anything.
    ##
    ## ```
    ## Url.from_str("https://example.com#stuff")
    ## ```
    ##
    ## URLs can be absolute, like `https://example.com`, or they can be relative, like `/blah`.
    ##
    ## ```
    ## Url.from_str("/this/is#relative")
    ## ```
    ##
    ## Since nothing is validated, this can return invalid URLs.
    ##
    ## ```
    ## Url.from_str("https://this is not a valid URL, not at all!")
    ## ```
    ##
    ## Naturally, passing invalid URLs to functions that need valid ones will tend to result in errors.
    ##
    from_str : Str -> Url
    from_str = |str| Url(str)

    ## Return a [Str] representation of this URL.
    ## ```
    ## # Gives "https://example.com/two%20words"
    ## Url.from_str("https://example.com")
    ##     .append("two words")
    ##     .to_str()
    ## ```
    to_str : Url -> Str
    to_str = |Url(str)| str

    ## [Percent-encodes](https://en.wikipedia.org/wiki/Percent-encoding) a
    ## [path component](https://en.wikipedia.org/wiki/Uniform_Resource_Identifier#Syntax)
    ## and appends to the end of the URL's path.
    ##
    ## This will be appended before any queries and fragments. If the given path string begins with `/` and the URL already ends with `/`, one
    ## will be ignored. This avoids turning a single slash into a double slash. If either the given URL or the given string is empty, no `/` will be added.
    append : Url, Str -> Url
    append = |Url(url_str), suffix_unencoded| {
        # percent-encode the suffix but not the slashes
        suffix =
            Str.join_with(
                Str.split_on(suffix_unencoded, "/").map(percent_encode),
                "/",
            )

        match str_split_first(url_str, "?") {
            Ok({ before, after }) => {
                prefix = append_help(before, suffix)
                Url(Str.concat(Str.concat(prefix, "?"), after))
            }

            Err(NotFound) =>
                # There wasn't a query, but there might still be a fragment
                match str_split_first(url_str, "#") {
                    Ok({ before, after }) => {
                        prefix = append_help(before, suffix)
                        Url(Str.concat(Str.concat(prefix, "#"), after))
                    }

                    Err(NotFound) =>
                        # No query and no fragment, so just append it
                        Url(append_help(url_str, suffix))
                }
        }
    }

    ## Internal helper
    append_help : Str, Str -> Str
    append_help = |prefix, suffix|
        if Str.ends_with(prefix, "/") {
            if Str.starts_with(suffix, "/") {
                # Avoid a double-slash by appending only the part of the suffix after the "/"
                match str_split_first(suffix, "/") {
                    Ok({ before: _, after }) => Str.concat(prefix, after)
                    Err(NotFound) => Str.concat(prefix, suffix)
                }
            } else {
                # prefix ends with "/" but suffix doesn't start with one, so just append.
                Str.concat(prefix, suffix)
            }
        } else if Str.starts_with(suffix, "/") {
            # Suffix starts with "/" but prefix doesn't end with one, so just append them.
            Str.concat(prefix, suffix)
        } else if Str.is_empty(prefix) {
            # Prefix is empty; return suffix.
            suffix
        } else if Str.is_empty(suffix) {
            # Suffix is empty; return prefix.
            prefix
        } else {
            # Neither is empty, but neither has a "/", so add one in between.
            Str.concat(Str.concat(prefix, "/"), suffix)
        }

    ## Internal helper. This is intentionally unexposed so that you don't accidentally
    ## double-encode things.
    percent_encode : Str -> Str
    percent_encode = |input| {
        # Optimistically assume we won't need any percent encoding, and can have
        # the same capacity as the input string. If we're wrong, it will get doubled.
        initial_output = List.with_capacity(Str.count_utf8_bytes(input))

        answer =
            List.fold(
                Str.to_utf8(input),
                initial_output,
                |output, byte|
                    # Spec for percent-encoding: https://www.ietf.org/rfc/rfc3986.txt
                    if
                        (byte >= 97 and byte <= 122) # lowercase ASCII
                        or (byte >= 65 and byte <= 90) # uppercase ASCII
                        or (byte >= 48 and byte <= 57) # digit
                    {
                        # This is the most common case: an unreserved character,
                        # which needs no encoding in a path
                        List.append(output, byte)
                    } else {
                        match byte {
                            46 | 95 | 126 | 150 =>
                                # These special characters can all be unescaped in paths
                                # ('.', '_', '~', '-')
                                List.append(output, byte)

                            _ => {
                                # This needs encoding in a path
                                suffix =
                                    List.sublist(
                                        Str.to_utf8(percent_encoded),
                                        { start: 3 * byte.to_u64(), len: 3 },
                                    )

                                List.concat(output, suffix)
                            }
                        }
                    },
            )

        match Str.from_utf8(answer) {
            Ok(s) => s
            Err(_) => "" # This should never fail
        }
    }

    ## Adds a [Str] query parameter to the end of the [Url].
    ##
    ## The key and value both get [percent-encoded](https://en.wikipedia.org/wiki/Percent-encoding).
    ##
    ## ```
    ## # Gives https://example.com?email=someone%40example.com
    ## Url.from_str("https://example.com")
    ##     .append_param("email", "someone@example.com")
    ## ```
    append_param : Url, Str, Str -> Url
    append_param = |Url(url_str), key, value| {
        { without_fragment, after_query } =
            match str_split_last(url_str, "#") {
                Ok({ before, after }) =>
                    # The fragment is almost certainly going to be a small string,
                    # so this interpolation should happen on the stack.
                    { without_fragment: before, after_query: "#${after}" }

                Err(NotFound) =>
                    { without_fragment: url_str, after_query: "" }
            }

        encoded_key = percent_encode(key)
        encoded_value = percent_encode(value)

        separator = if has_query(Url(without_fragment)) { "&" } else { "?" }

        Url(
            Str.concat(
                Str.concat(
                    Str.concat(
                        Str.concat(without_fragment, separator),
                        encoded_key,
                    ),
                    Str.concat("=", encoded_value),
                ),
                after_query,
            ),
        )
    }

    ## Replaces the URL's [query](https://en.wikipedia.org/wiki/URL#Syntax)—the part
    ## after the `?`, if it has one, but before any `#` it might have.
    ##
    ## Passing `""` removes the `?` (if there was one).
    with_query : Url, Str -> Url
    with_query = |Url(url_str), query_str| {
        { without_fragment, after_query } =
            match str_split_last(url_str, "#") {
                Ok({ before, after }) =>
                    { without_fragment: before, after_query: "#${after}" }

                Err(NotFound) =>
                    { without_fragment: url_str, after_query: "" }
            }

        before_query =
            match str_split_last(without_fragment, "?") {
                Ok({ before, after: _ }) => before
                Err(NotFound) => without_fragment
            }

        if Str.is_empty(query_str) {
            Url(Str.concat(before_query, after_query))
        } else {
            Url(
                Str.concat(
                    Str.concat(Str.concat(before_query, "?"), query_str),
                    after_query,
                ),
            )
        }
    }

    ## Returns the URL's [query](https://en.wikipedia.org/wiki/URL#Syntax)—the part after
    ## the `?`, if it has one, but before any `#` it might have.
    ##
    ## Returns `""` if the URL has no query.
    query : Url -> Str
    query = |Url(url_str)| {
        without_fragment =
            match str_split_last(url_str, "#") {
                Ok({ before, after: _ }) => before
                Err(NotFound) => url_str
            }

        match str_split_last(without_fragment, "?") {
            Ok({ before: _, after }) => after
            Err(NotFound) => ""
        }
    }

    ## Returns [Bool.True] if the URL has a `?` in it.
    has_query : Url -> Bool
    has_query = |Url(url_str)|
        Str.contains(url_str, "?")

    ## Returns the URL's [fragment](https://en.wikipedia.org/wiki/URL#Syntax)—the part after
    ## the `#`, if it has one.
    ##
    ## Returns `""` if the URL has no fragment.
    fragment : Url -> Str
    fragment = |Url(url_str)|
        match str_split_last(url_str, "#") {
            Ok({ before: _, after }) => after
            Err(NotFound) => ""
        }

    ## Replaces the URL's [fragment](https://en.wikipedia.org/wiki/URL#Syntax).
    ##
    ## If the URL didn't have a fragment, adds one. Passing `""` removes the fragment.
    with_fragment : Url, Str -> Url
    with_fragment = |Url(url_str), fragment_str|
        match str_split_last(url_str, "#") {
            Ok({ before, after: _ }) =>
                if Str.is_empty(fragment_str) {
                    # If the given fragment is empty, remove the URL's fragment
                    Url(before)
                } else {
                    # Replace the URL's old fragment with this one, discarding `after`
                    Url("${before}#${fragment_str}")
                }

            Err(NotFound) =>
                if Str.is_empty(fragment_str) {
                    # If the given fragment is empty, leave the URL as having no fragment
                    Url(url_str)
                } else {
                    # The URL didn't have a fragment, so give it this one
                    Url("${url_str}#${fragment_str}")
                }
        }

    ## Returns [Bool.True] if the URL has a `#` in it.
    has_fragment : Url -> Bool
    has_fragment = |Url(url_str)|
        Str.contains(url_str, "#")

    # Adapted from the percent-encoding crate, © The rust-url developers, Apache2-licensed
    #
    # https://github.com/servo/rust-url/blob/e12d76a61add5bc09980599c738099feaacd1d0d/percent_encoding/src/lib.rs#L183
    percent_encoded : Str
    percent_encoded = "%00%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F%20%21%22%23%24%25%26%27%28%29%2A%2B%2C%2D%2E%2F%30%31%32%33%34%35%36%37%38%39%3A%3B%3C%3D%3E%3F%40%41%42%43%44%45%46%47%48%49%4A%4B%4C%4D%4E%4F%50%51%52%53%54%55%56%57%58%59%5A%5B%5C%5D%5E%5F%60%61%62%63%64%65%66%67%68%69%6A%6B%6C%6D%6E%6F%70%71%72%73%74%75%76%77%78%79%7A%7B%7C%7D%7E%7F%80%81%82%83%84%85%86%87%88%89%8A%8B%8C%8D%8E%8F%90%91%92%93%94%95%96%97%98%99%9A%9B%9C%9D%9E%9F%A0%A1%A2%A3%A4%A5%A6%A7%A8%A9%AA%AB%AC%AD%AE%AF%B0%B1%B2%B3%B4%B5%B6%B7%B8%B9%BA%BB%BC%BD%BE%BF%C0%C1%C2%C3%C4%C5%C6%C7%C8%C9%CA%CB%CC%CD%CE%CF%D0%D1%D2%D3%D4%D5%D6%D7%D8%D9%DA%DB%DC%DD%DE%DF%E0%E1%E2%E3%E4%E5%E6%E7%E8%E9%EA%EB%EC%ED%EE%EF%F0%F1%F2%F3%F4%F5%F6%F7%F8%F9%FA%FB%FC%FD%FE%FF"

    query_params : Url -> Dict(Str, Str)
    query_params = |url|
        Str.split_on(query(url), "&")
            .fold(
                Dict.empty(),
                |dict, pair|
                    match str_split_first(pair, "=") {
                        Ok({ before, after }) => Dict.insert(dict, before, after)
                        Err(NotFound) => Dict.insert(dict, pair, "")
                    },
            )

    ## Returns the URL's [path](https://en.wikipedia.org/wiki/URL#Syntax)—the part after
    ## the scheme and authority (e.g. `https://`) but before any `?` or `#` it might have.
    ##
    ## Returns `""` if the URL has no path.
    path : Url -> Str
    path = |Url(url_str)| {
        without_authority =
            if Str.starts_with(url_str, "/") {
                url_str
            } else {
                match str_split_first(url_str, ":") {
                    Ok({ before: _, after }) =>
                        match str_split_first(after, "//") {
                            # Only drop the `//` if it's right after the `://` like in `https://`
                            # (so, `before` is empty) - otherwise, the `//` is part of the path!
                            Ok({ before, after: after_slashes }) if Str.is_empty(before) => after_slashes
                            _ => after
                        }

                    # There's no `//` and also no `:` so this must be a path-only URL, e.g. "/foo?bar=baz#blah"
                    Err(NotFound) => url_str
                }
            }

        # Drop the query and/or fragment
        match str_split_last(without_authority, "?") {
            Ok({ before, after: _ }) => before
            Err(NotFound) =>
                match str_split_last(without_authority, "#") {
                    Ok({ before, after: _ }) => before
                    Err(NotFound) => without_authority
                }
        }
    }

    # Internal helper: like the old `Str.split_first`. Splits on the first
    # occurrence of `delim`, returning the part before and the part after.
    str_split_first : Str, Str -> Try({ before : Str, after : Str }, [NotFound])
    str_split_first = |s, delim| {
        parts = Str.split_on(s, delim)
        match parts {
            [before, .. as rest] if List.len(rest) > 0 =>
                Ok({ before: before, after: Str.join_with(rest, delim) })

            _ => Err(NotFound)
        }
    }

    # Internal helper: like the old `Str.split_last`. Splits on the last
    # occurrence of `delim`, returning the part before and the part after.
    str_split_last : Str, Str -> Try({ before : Str, after : Str }, [NotFound])
    str_split_last = |s, delim| {
        parts = Str.split_on(s, delim)
        n = List.len(parts)
        if n <= 1 {
            Err(NotFound)
        } else {
            before_parts = List.sublist(parts, { start: 0, len: n - 1 })
            match List.last(parts) {
                Ok(after) => Ok({ before: Str.join_with(before_parts, delim), after: after })
                Err(_) => Err(NotFound)
            }
        }
    }
}

# `Url.path` supports non-encoded URIs in query parameters (https://datatracker.ietf.org/doc/html/rfc3986#section-3.4)
expect {
    input = Url.from_str("https://example.com/foo/bar?key1=https://www.baz.com/some-path#stuff")
    expected = "example.com/foo/bar"
    Url.path(input) == expected
}

# `Url.path` supports non-encoded URIs in query parameters (https://datatracker.ietf.org/doc/html/rfc3986#section-3.4)
expect {
    input = Url.from_str("/foo/bar?key1=https://www.baz.com/some-path#stuff")
    output = Url.path(input)
    expected = "/foo/bar"
    output == expected
}
