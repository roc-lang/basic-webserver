## Encode arbitrary bytes using standard padded Base64 from
## [RFC 4648](https://www.rfc-editor.org/rfc/rfc4648.html#section-4).
##
## Output uses the standard `A-Z`, `a-z`, `0-9`, `+`, `/` alphabet, includes
## `=` padding, and never contains line breaks. This is not URL-safe or
## unpadded Base64.
Base64 := [].{

	## Encode arbitrary bytes as an ASCII string.
	##
	## Input does not need to be valid UTF-8. The output length is exactly four
	## bytes for every three input bytes, rounded up to a complete group:
	## `4 * ceil(input byte count / 3)`.
	encode : List(U8) -> Str
	encode = |bytes| Str.from_utf8_lossy(encode_bytes(bytes, []))
}

alphabet : List(U8)
alphabet = Str.to_utf8("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

encode_bytes : List(U8), List(U8) -> List(U8)
encode_bytes = |remaining, out|
	match remaining {
		[] => out
		[a] => append_quad(out, a, 0, 0, 1)
		[a, b] => append_quad(out, a, b, 0, 2)
		[a, b, c, .. as rest] => encode_bytes(rest, append_quad(out, a, b, c, 3))
	}

append_quad : List(U8), U8, U8, U8, U64 -> List(U8)
append_quad = |out, a, b, c, byte_count| {
	bits = a.to_u64() * 65_536 + b.to_u64() * 256 + c.to_u64()
	first = alphabet_byte(bits // 262_144)
	second = alphabet_byte((bits // 4_096) % 64)
	third = alphabet_byte((bits // 64) % 64)
	fourth = alphabet_byte(bits % 64)

	match byte_count {
		1 => out.append(first).append(second).append('=').append('=')
		2 => out.append(first).append(second).append(third).append('=')
		_ => out.append(first).append(second).append(third).append(fourth)
	}
}

alphabet_byte : U64 -> U8
alphabet_byte = |index| alphabet.get(index) ?? 'A'

## Encoding matches the RFC 4648 section 10 test vectors.
expect {
	Base64.encode(Str.to_utf8("")) == ""
		and Base64.encode(Str.to_utf8("f")) == "Zg=="
			and Base64.encode(Str.to_utf8("fo")) == "Zm8="
				and Base64.encode(Str.to_utf8("foo")) == "Zm9v"
					and Base64.encode(Str.to_utf8("foob")) == "Zm9vYg=="
						and Base64.encode(Str.to_utf8("fooba")) == "Zm9vYmE="
							and Base64.encode(Str.to_utf8("foobar")) == "Zm9vYmFy"
}

## Encoding accepts arbitrary non-UTF-8 bytes.
expect Base64.encode([0x00, 0xFF, 0x80, 0xFE]) == "AP+A/g=="

## One- and two-byte binary tails receive standard padding.
expect {
	Base64.encode([0xFF]) == "/w=="
		and Base64.encode([0xFF, 0xEE]) == "/+4="
}
