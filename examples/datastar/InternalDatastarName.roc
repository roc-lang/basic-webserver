## Shared implementation for Datastar names which use a restricted ASCII form.
InternalDatastarName :: [].{

	valid_signal : Str -> Bool
	valid_signal = |value| {
		bytes = Str.to_utf8(value)
		match bytes {
			[first, .. as rest] => ascii_letter(first) and rest.all(ascii_letter_or_digit)
			[] => Bool.False
		}
	}

	valid_element_id : Str -> Bool
	valid_element_id = |value| {
		bytes = Str.to_utf8(value)
		match bytes {
			[first, .. as rest] =>
				ascii_letter(first) and
					rest.all(|byte| ascii_letter_or_digit(byte) or byte == 45 or byte == 95)
			[] => Bool.False
		}
	}

	attribute_name : Str -> Str
	attribute_name = |value|
		Str.from_utf8_lossy(
			Str.to_utf8(value).fold(
				[],
				|bytes, byte|
					if byte >= 65 and byte <= 90 {
						bytes.concat([45, byte + 32])
					} else {
						bytes.append(byte)
					},
			),
		)
}

ascii_letter : U8 -> Bool
ascii_letter = |byte| (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)

ascii_letter_or_digit : U8 -> Bool
ascii_letter_or_digit = |byte| ascii_letter(byte) or (byte >= 48 and byte <= 57)
