import http.Header

## Parse request cookies and render strict `Set-Cookie` response headers.
##
## Request parsing preserves field order, cookie order, duplicate names, name
## case, and value bytes. It does not decode or reinterpret cookie values.
## Rendering follows the well-behaved server profile from RFC6265bis and
## returns one header record for one cookie.
Cookie := [].{

	## One name/value pair from a request `Cookie` field.
	Pair : { name : Str, value : Str }

	## The location of an invalid pair within the complete request header list.
	Location : { header_index : U64, pair_index : U64 }

	## A strict request-cookie parse failure.
	ParseErr : [
		EmptyCookiePair(Location),
		MissingCookieEquals(Location),
		InvalidCookieName(Location),
		InvalidCookieValue(Location),
	]

	## The supported `SameSite` policies.
	SameSite : [Lax, None, Strict]

	## Attributes for one response cookie.
	SetCookie : {
		name : Str,
		value : Str,
		path : [Absent, Present(Str)],
		domain : [Absent, Present(Str)],
		max_age_seconds : [Absent, Present(U64)],
		secure : Bool,
		http_only : Bool,
		same_site : [Absent, Present(SameSite)],
	}

	## Scope and security attributes needed to delete a cookie.
	##
	## `path` and `domain` must match the cookie being deleted. `secure` should
	## match the original cookie and is required for prefixed cookie names.
	DeleteCookie : {
		name : Str,
		path : [Absent, Present(Str)],
		domain : [Absent, Present(Str)],
		secure : Bool,
	}

	## A response-cookie validation failure.
	SetErr : [
		InvalidCookieName,
		InvalidCookieValue,
		InvalidCookiePath,
		InvalidCookieDomain,
		SameSiteNoneRequiresSecure,
		SecurePrefixRequiresSecure,
		HostPrefixRequiresSecure,
		HostPrefixRequiresRootPath,
		HostPrefixForbidsDomain,
	]

	## Parse every case-insensitive `Cookie` request header.
	##
	## Fields and pairs are processed in received order. Duplicate names and
	## case-distinct names remain separate list entries. Space and horizontal
	## tab around pairs and `=` are ignored; values themselves must match the
	## cookie-value grammar.
	parse_request : List(Header.Header) -> Try(List(Pair), ParseErr)
	parse_request = |headers| parse_headers(headers, 0, [])

	## Return the one value for a case-sensitive cookie name.
	##
	## Absence is explicit. More than one match is an error rather than an
	## order-dependent choice.
	get_unique : List(Pair), Str -> Try([Absent, Present(Str)], [DuplicateCookie(Str)])
	get_unique = |cookies, name| get_unique_help(cookies, name, Absent)

	## Render one validated `Set-Cookie` header.
	##
	## Values are emitted exactly as supplied. `Max-Age=0` is accepted for
	## deletion; positive values represent a finite lifetime.
	set_header : SetCookie -> Try(Header.Header, SetErr)
	set_header = |cookie| {
		validate_set_cookie(cookie)?

		value = "${cookie.name}=${cookie.value}"
		with_path =
			match cookie.path {
				Absent => value
				Present(path) => "${value}; Path=${path}"
			}
		with_domain =
			match cookie.domain {
				Absent => with_path
				Present(domain) => "${with_path}; Domain=${domain}"
			}
		with_max_age =
			match cookie.max_age_seconds {
				Absent => with_domain
				Present(seconds) => "${with_domain}; Max-Age=${seconds.to_str()}"
			}
		with_secure = if cookie.secure {
			"${with_max_age}; Secure"
		} else {
			with_max_age
		}
		with_http_only = if cookie.http_only {
			"${with_secure}; HttpOnly"
		} else {
			with_secure
		}
		complete =
			match cookie.same_site {
				Absent => with_http_only
				Present(policy) => "${with_http_only}; SameSite=${same_site_str(policy)}"
			}

		Ok({ name: "Set-Cookie", value: complete })
	}

	## Render a deletion cookie with the original Path and Domain scope.
	##
	## The result has an empty value and `Max-Age=0`.
	delete_header : DeleteCookie -> Try(Header.Header, SetErr)
	delete_header = |cookie|
		set_header({
			name: cookie.name,
			value: "",
			path: cookie.path,
			domain: cookie.domain,
			max_age_seconds: Present(0),
			secure: cookie.secure,
			http_only: False,
			same_site: Absent,
		})
}

parse_headers : List(Header.Header), U64, List(Cookie.Pair) -> Try(List(Cookie.Pair), Cookie.ParseErr)
parse_headers = |headers, header_index, out|
	match headers {
		[] => Ok(out)
		[{ name, value }, .. as rest] =>
			if ascii_lower(name) == "cookie" {
				next = parse_pairs(Str.split_on(value, ";"), header_index, 0, out)?
				parse_headers(rest, header_index + 1, next)
			} else {
				parse_headers(rest, header_index + 1, out)
			}
		}

parse_pairs : List(Str), U64, U64, List(Cookie.Pair) -> Try(List(Cookie.Pair), Cookie.ParseErr)
parse_pairs = |parts, header_index, pair_index, out|
	match parts {
		[] => Ok(out)
		[first, .. as rest] => {
			location = { header_index, pair_index }
			part = trim_ows(first)
			if Str.is_empty(part) {
				Err(EmptyCookiePair(location))
			} else {
				bytes = Str.to_utf8(part)
				equals_index = find_byte(bytes, '=', 0)
				if equals_index == bytes.len() {
					Err(MissingCookieEquals(location))
				} else {
					name = trim_ows(Str.from_utf8_lossy(bytes.sublist({ start: 0, len: equals_index })))
					value = trim_ows(
						Str.from_utf8_lossy(
							bytes.sublist({
								start: equals_index + 1,
								len: bytes.len() - equals_index - 1,
							}),
						),
					)
					if Bool.not(valid_cookie_name(name)) {
						Err(InvalidCookieName(location))
					} else if Bool.not(valid_cookie_value(value)) {
						Err(InvalidCookieValue(location))
					} else {
						parse_pairs(
							rest,
							header_index,
							pair_index + 1,
							out.append({ name, value }),
						)
					}
				}
			}
		}
	}

get_unique_help : List(Cookie.Pair), Str, [Absent, Present(Str)] -> Try([Absent, Present(Str)], [DuplicateCookie(Str)])
get_unique_help = |cookies, wanted, found|
	match cookies {
		[] => Ok(found)
		[{ name, value }, .. as rest] =>
			if name == wanted {
				match found {
					Absent => get_unique_help(rest, wanted, Present(value))
					Present(_) => Err(DuplicateCookie(wanted))
				}
			} else {
				get_unique_help(rest, wanted, found)
			}
		}

validate_set_cookie : Cookie.SetCookie -> Try({}, Cookie.SetErr)
validate_set_cookie = |cookie| {
	if Bool.not(valid_cookie_name(cookie.name)) {
		return Err(InvalidCookieName)
	}
	if Bool.not(valid_cookie_value(cookie.value)) {
		return Err(InvalidCookieValue)
	}
	match cookie.path {
		Present(path) if Bool.not(valid_path(path)) => return Err(InvalidCookiePath)
		_ => {}
	}
	match cookie.domain {
		Present(domain) if Bool.not(valid_domain(domain)) => return Err(InvalidCookieDomain)
		_ => {}
	}
	match cookie.same_site {
		Present(None) if Bool.not(cookie.secure) => return Err(SameSiteNoneRequiresSecure)
		_ => {}
	}
	if starts_with(cookie.name, "__Secure-") and Bool.not(cookie.secure) {
		return Err(SecurePrefixRequiresSecure)
	}
	if starts_with(cookie.name, "__Host-") {
		if Bool.not(cookie.secure) {
			return Err(HostPrefixRequiresSecure)
		}
		match cookie.path {
			Present("/") => {}
			_ => return Err(HostPrefixRequiresRootPath)
		}
		match cookie.domain {
			Absent => {}
			Present(_) => return Err(HostPrefixForbidsDomain)
		}
	}
	Ok({})
}

valid_cookie_name : Str -> Bool
valid_cookie_name = |name| {
	bytes = Str.to_utf8(name)
	Bool.not(bytes.is_empty()) and bytes.all(is_token_byte)
}

valid_cookie_value : Str -> Bool
valid_cookie_value = |value| {
	bytes = Str.to_utf8(value)
	if bytes.len() >= 2 and get_or_zero(bytes, 0) == '"' and get_or_zero(bytes, bytes.len() - 1) == '"' {
		bytes.sublist({ start: 1, len: bytes.len() - 2 }).all(is_cookie_octet)
	} else {
		bytes.all(is_cookie_octet)
	}
}

valid_path : Str -> Bool
valid_path = |path| Str.to_utf8(path).all(is_attribute_octet)

valid_domain : Str -> Bool
valid_domain = |domain| {
	bytes = Str.to_utf8(domain)
	Bool.not(bytes.is_empty())
		and bytes.len() <= 253
			and valid_domain_labels(Str.split_on(domain, "."))
}

valid_domain_labels : List(Str) -> Bool
valid_domain_labels = |labels|
	match labels {
		[] => True
		[first, .. as rest] => {
			bytes = Str.to_utf8(first)
			Bool.not(bytes.is_empty())
				and bytes.len() <= 63
					and is_alphanumeric(get_or_zero(bytes, 0))
						and is_alphanumeric(get_or_zero(bytes, bytes.len() - 1))
							and bytes.all(|byte| is_alphanumeric(byte) or byte == '-')
								and valid_domain_labels(rest)
		}
	}

same_site_str : Cookie.SameSite -> Str
same_site_str = |policy|
	match policy {
		Lax => "Lax"
		None => "None"
		Strict => "Strict"
	}

ascii_lower : Str -> Str
ascii_lower = |input|
	Str.from_utf8_lossy(
		Str.to_utf8(input).map(
			|byte|
				if byte >= 'A' and byte <= 'Z' {
					byte + 32
				} else {
					byte
				},
		),
	)

trim_ows : Str -> Str
trim_ows = |input| {
	bytes = Str.to_utf8(input)
	start = trim_ows_start(bytes, 0)
	end = trim_ows_end(bytes, bytes.len())
	length = if end > start {
		end - start
	} else {
		0
	}
	Str.from_utf8_lossy(bytes.sublist({ start, len: length }))
}

trim_ows_start : List(U8), U64 -> U64
trim_ows_start = |bytes, index|
	if index < bytes.len() and is_ows(get_or_zero(bytes, index)) {
		trim_ows_start(bytes, index + 1)
	} else {
		index
	}

trim_ows_end : List(U8), U64 -> U64
trim_ows_end = |bytes, end|
	if end > 0 and is_ows(get_or_zero(bytes, end - 1)) {
		trim_ows_end(bytes, end - 1)
	} else {
		end
	}

find_byte : List(U8), U8, U64 -> U64
find_byte = |bytes, wanted, index|
	if index >= bytes.len() {
		index
	} else if get_or_zero(bytes, index) == wanted {
		index
	} else {
		find_byte(bytes, wanted, index + 1)
	}

starts_with : Str, Str -> Bool
starts_with = |value, prefix| List.starts_with(Str.to_utf8(value), Str.to_utf8(prefix))

get_or_zero : List(U8), U64 -> U8
get_or_zero = |bytes, index| bytes.get(index) ?? 0

is_ows : U8 -> Bool
is_ows = |byte| byte == ' ' or byte == '\t'

is_token_byte : U8 -> Bool
is_token_byte = |byte|
	is_alphanumeric(byte)
		or byte == '!'
			or byte == '#'
				or byte == '$'
					or byte == '%'
						or byte == '&'
							or byte == '\''
								or byte == '*'
									or byte == '+'
										or byte == '-'
											or byte == '.'
												or byte == '^'
													or byte == '_'
														or byte == '`'
															or byte == '|'
																or byte == '~'

is_cookie_octet : U8 -> Bool
is_cookie_octet = |byte|
	byte == 0x21
		or (byte >= 0x23 and byte <= 0x2B)
			or (byte >= 0x2D and byte <= 0x3A)
				or (byte >= 0x3C and byte <= 0x5B)
					or (byte >= 0x5D and byte <= 0x7E)

is_attribute_octet : U8 -> Bool
is_attribute_octet = |byte|
	(byte >= 0x20 and byte <= 0x3A)
		or (byte >= 0x3C and byte <= 0x7E)

is_alphanumeric : U8 -> Bool
is_alphanumeric = |byte|
	(byte >= '0' and byte <= '9')
		or (byte >= 'A' and byte <= 'Z')
			or (byte >= 'a' and byte <= 'z')

test_set_cookie : Cookie.SetCookie
test_set_cookie = {
	name: "session",
	value: "abc123",
	path: Present("/"),
	domain: Absent,
	max_age_seconds: Present(3600),
	secure: True,
	http_only: True,
	same_site: Present(Lax),
}

## Request parsing preserves every field, duplicate, case, empty value, and
## quoted value while tolerating surrounding SP and HTAB.
expect {
	headers = [
		{ name: "Host", value: "example.test" },
		{ name: "Cookie", value: " session = abc ; theme=dark; empty= " },
		{ name: "cOoKiE", value: "session=shadow;\tSESSION=upper; quoted=\"abc\"" },
	]
	Cookie.parse_request(headers) == Ok([
		{ name: "session", value: "abc" },
		{ name: "theme", value: "dark" },
		{ name: "empty", value: "" },
		{ name: "session", value: "shadow" },
		{ name: "SESSION", value: "upper" },
		{ name: "quoted", value: "\"abc\"" },
	])
}

## Values may contain equals signs and all valid cookie octets.
expect Cookie.parse_request([{ name: "Cookie", value: "token=a=b==; encoded=%2F; symbols=!#$%&'*+-.:<>?[]^_`|~" }]) == Ok([
	{ name: "token", value: "a=b==" },
	{ name: "encoded", value: "%2F" },
	{ name: "symbols", value: "!#$%&'*+-.:<>?[]^_`|~" },
])

## Requests without Cookie fields produce an empty list.
expect Cookie.parse_request([{ name: "Accept", value: "*/*" }]) == Ok([])

## Unique lookup is case-sensitive and never chooses between duplicates.
expect {
	cookies = [
		{ name: "session", value: "first" },
		{ name: "SESSION", value: "upper" },
		{ name: "session", value: "second" },
	]
	Cookie.get_unique(cookies, "SESSION") == Ok(Present("upper"))
		and Cookie.get_unique(cookies, "missing") == Ok(Absent)
			and Cookie.get_unique(cookies, "session") == Err(DuplicateCookie("session"))
}

## Empty pairs, missing equals, invalid names, and invalid values are typed.
expect {
	Cookie.parse_request([{ name: "Cookie", value: "" }]) == Err(
		EmptyCookiePair({ header_index: 0, pair_index: 0 }),
	) and
		Cookie.parse_request([{ name: "Cookie", value: " \t " }]) == Err(
			EmptyCookiePair({ header_index: 0, pair_index: 0 }),
		) and
			Cookie.parse_request([{ name: "Cookie", value: "name" }]) == Err(
				MissingCookieEquals({ header_index: 0, pair_index: 0 }),
			) and
				Cookie.parse_request([{ name: "Cookie", value: "bad name=value" }]) == Err(
					InvalidCookieName({ header_index: 0, pair_index: 0 }),
				) and
					Cookie.parse_request([{ name: "Cookie", value: "name=bad,value" }]) == Err(
						InvalidCookieValue({ header_index: 0, pair_index: 0 }),
					)
}

## Control characters, non-ASCII bytes, malformed quoting, and backslashes are
## rejected instead of entering an HTTP response or being reinterpreted.
expect {
	Cookie.parse_request([{ name: "Cookie", value: "name=line\r\nbreak" }]) == Err(
		InvalidCookieValue({ header_index: 0, pair_index: 0 }),
	) and
		Cookie.parse_request([{ name: "Cookie", value: "name=café" }]) == Err(
			InvalidCookieValue({ header_index: 0, pair_index: 0 }),
		) and
			Cookie.parse_request([{ name: "Cookie", value: "name=\"unterminated" }]) == Err(
				InvalidCookieValue({ header_index: 0, pair_index: 0 }),
			) and
				Cookie.parse_request([{ name: "Cookie", value: "name=bad\\value" }]) == Err(
					InvalidCookieValue({ header_index: 0, pair_index: 0 }),
				)
}

## Rendering uses a deterministic attribute order and the requested policies.
expect Cookie.set_header(test_set_cookie) == Ok({
	name: "Set-Cookie",
	value: "session=abc123; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=Lax",
})

## Name, value, Path, and Domain grammar is enforced.
expect {
	Cookie.set_header({ ..test_set_cookie, name: "" }) == Err(InvalidCookieName)
		and Cookie.set_header({ ..test_set_cookie, name: "bad name" }) == Err(InvalidCookieName)
			and Cookie.set_header({ ..test_set_cookie, name: "bad\r\nSet-Cookie" }) == Err(InvalidCookieName)
				and Cookie.set_header({ ..test_set_cookie, name: "café" }) == Err(InvalidCookieName)
					and Cookie.set_header({ ..test_set_cookie, value: "bad,value" }) == Err(InvalidCookieValue)
						and Cookie.set_header({ ..test_set_cookie, value: "bad;value" }) == Err(InvalidCookieValue)
							and Cookie.set_header({ ..test_set_cookie, value: "bad\r\nSet-Cookie: injected" }) == Err(InvalidCookieValue)
								and Cookie.set_header({ ..test_set_cookie, value: "café" }) == Err(InvalidCookieValue)
									and Cookie.set_header({ ..test_set_cookie, path: Present("/bad; Secure") }) == Err(InvalidCookiePath)
										and Cookie.set_header({ ..test_set_cookie, domain: Present(".example.test") }) == Err(InvalidCookieDomain)
											and Cookie.set_header({ ..test_set_cookie, domain: Present("bad_domain.test") }) == Err(InvalidCookieDomain)
}

## SameSite=None and security prefixes enforce their browser-visible contract.
expect {
	Cookie.set_header({ ..test_set_cookie, same_site: Present(None), secure: False }) == Err(SameSiteNoneRequiresSecure)
		and Cookie.set_header({ ..test_set_cookie, name: "__Secure-session", secure: False }) == Err(SecurePrefixRequiresSecure)
			and Cookie.set_header({ ..test_set_cookie, name: "__Host-session", secure: False }) == Err(HostPrefixRequiresSecure)
				and Cookie.set_header({ ..test_set_cookie, name: "__Host-session", path: Absent }) == Err(HostPrefixRequiresRootPath)
					and Cookie.set_header({ ..test_set_cookie, name: "__Host-session", domain: Present("example.test") }) == Err(HostPrefixForbidsDomain)
						and Cookie.set_header({ ..test_set_cookie, name: "__Host-session" }) == Ok({
							name: "Set-Cookie",
							value: "__Host-session=abc123; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=Lax",
						})
}

## Every SameSite policy renders as its canonical spelling.
expect {
	Cookie.set_header({ ..test_set_cookie, same_site: Present(None) }) == Ok({
		name: "Set-Cookie",
		value: "session=abc123; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=None",
	}) and
		Cookie.set_header({ ..test_set_cookie, same_site: Present(Strict) }) == Ok({
			name: "Set-Cookie",
			value: "session=abc123; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=Strict",
		})
}

## Prefix matching is case-sensitive in the server production profile.
expect Cookie.set_header({ ..test_set_cookie, name: "__host-session", secure: False }) == Ok({
	name: "Set-Cookie",
	value: "__host-session=abc123; Path=/; Max-Age=3600; HttpOnly; SameSite=Lax",
})

## Deletion preserves scope and emits an empty value with Max-Age=0.
expect Cookie.delete_header({
	name: "session",
	path: Present("/account"),
	domain: Present("example.test"),
	secure: True,
}) == Ok({
	name: "Set-Cookie",
	value: "session=; Path=/account; Domain=example.test; Max-Age=0; Secure",
})

## Independent cookie results remain independent response header fields.
expect {
	first = Cookie.set_header(test_set_cookie)?
	second = Cookie.delete_header({
		name: "theme",
		path: Present("/"),
		domain: Absent,
		secure: True,
	})?
	[first, second] == [
		{
			name: "Set-Cookie",
			value: "session=abc123; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=Lax",
		},
		{ name: "Set-Cookie", value: "theme=; Path=/; Max-Age=0; Secure" },
	]
}
