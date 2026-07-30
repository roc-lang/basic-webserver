import IOErr exposing [IOErr]
import Host
import OsStr exposing [OsStr]
import UnixTime exposing [UnixTime]

path_type_from_host : Host.PathType -> [IsFile, IsDir, IsSymLink, IsOther]
path_type_from_host = |path_type|
	if path_type.is_sym_link {
		IsSymLink
	} else if path_type.is_dir {
		IsDir
	} else if path_type.is_file {
		IsFile
	} else {
		IsOther
	}

timestamp_from_host : I128 -> UnixTime.Timestamp
timestamp_from_host = |nanos|
	match UnixTime.Timestamp.from_nanos_since_epoch(nanos) {
		Ok(timestamp) => timestamp
		Err(OutOfRange) => {
			crash "host file timestamp is outside the UnixTime.Timestamp range"
		}
	}

## Construct and operate on byte-preserving paths. Native Unix
## bytes and Windows UTF-16 units are preserved across host effects; use
## `display` only when a lossy human-readable representation is appropriate.
Path := [
	Utf8(Str),
	Unix(List(U8)),
	Windows(List(U16)),
].{

	## Create a path from an OS string value, preserving raw OS units.
	from_os_str : OsStr -> Path
	from_os_str = |os_str| from_raw(OsStr.to_raw(os_str))

	## Convert a path to an OS string value, preserving raw OS units.
	to_os_str : Path -> OsStr
	to_os_str = |path| OsStr.from_raw(to_raw(path))

	## Returns `Bool.True` if the path exists on disk and is pointing at a regular file.
	##
	## This function does not traverse symbolic links; symbolic links (including
	## broken ones) return `Bool.False`.
	## Sockets, FIFOs, devices, and other special filesystem objects also return `Bool.False`.
	is_file! : Path => Try(Bool, [PathErr(IOErr), ..])
	is_file! = |path|
		match type!(path) {
			Ok(IsFile) => Ok(Bool.True)
			Ok(_) => Ok(Bool.False)
			Err(PathErr(NotFound)) => Ok(Bool.False)
			Err(err) => Err(err)
		}

	## Returns `Bool.True` if the path exists on disk and is pointing at a directory.
	##
	## This function does not traverse symbolic links; symbolic links (including
	## broken ones) return `Bool.False`.
	## Sockets, FIFOs, devices, and other special filesystem objects also return `Bool.False`.
	is_dir! : Path => Try(Bool, [PathErr(IOErr), ..])
	is_dir! = |path|
		match type!(path) {
			Ok(IsDir) => Ok(Bool.True)
			Ok(_) => Ok(Bool.False)
			Err(PathErr(NotFound)) => Ok(Bool.False)
			Err(err) => Err(err)
		}

	## Returns `Bool.True` if the path exists on disk and is pointing at a symbolic link.
	##
	## This function will not traverse symbolic links - it checks whether the path
	## itself is a symlink.
	## Sockets, FIFOs, devices, and other special filesystem objects return `Bool.False`.
	is_sym_link! : Path => Try(Bool, [PathErr(IOErr), ..])
	is_sym_link! = |path|
		match type!(path) {
			Ok(IsSymLink) => Ok(Bool.True)
			Ok(_) => Ok(Bool.False)
			Err(PathErr(NotFound)) => Ok(Bool.False)
			Err(err) => Err(err)
		}

	## Returns `True` if the path exists on disk.
	exists! : Path => Try(Bool, [PathErr(IOErr), ..])
	exists! = |path|
		match type!(path) {
			Ok(_) => Ok(Bool.True)
			Err(PathErr(NotFound)) => Ok(Bool.False)
			Err(err) => Err(err)
		}

	## Return the type of the path if the path exists on disk.
	##
	## `IsOther` represents sockets, FIFOs, block and character devices, and any
	## platform-specific object that is not a regular file, directory, or symbolic
	## link. On Windows this includes unrecognized reparse-point types.
	type! : Path => Try([IsFile, IsDir, IsSymLink, IsOther], [PathErr(IOErr), ..])
	type! = |path| {
		Host.path_type!(to_host_raw!(path))
			.map_err(|err| PathErr(err))
			.map_ok(path_type_from_host)
	}

	## Read all bytes from a file at this path.
	read_bytes! : Path => Try(List(U8), [PathErr(IOErr), ..])
	read_bytes! = |path| map_file_result(Host.file_read_bytes!(to_host_raw!(path)))

	## Write bytes to a file at this path, replacing any existing contents.
	write_bytes! : Path, List(U8) => Try({}, [PathErr(IOErr), ..])
	write_bytes! = |path, bytes| map_file_result(Host.file_write_bytes!(to_host_raw!(path), bytes))

	## Read a UTF-8 file at this path.
	read_utf8! : Path => Try(Str, [PathErr(IOErr), ..])
	read_utf8! = |path| map_file_result(Host.file_read_utf8!(to_host_raw!(path)))

	## Write a UTF-8 file at this path, replacing any existing contents.
	write_utf8! : Path, Str => Try({}, [PathErr(IOErr), ..])
	write_utf8! = |path, content| map_file_result(Host.file_write_utf8!(to_host_raw!(path), content))

	## Delete a file at this path.
	delete! : Path => Try({}, [PathErr(IOErr), ..])
	delete! = |path| map_file_result(Host.file_delete!(to_host_raw!(path)))

	## Return the size of the file at this path in bytes.
	size_in_bytes! : Path => Try(U64, [PathErr(IOErr), ..])
	size_in_bytes! = |path| map_file_result(Host.file_size_in_bytes!(to_host_raw!(path)))

	## Check whether the file is executable under the native platform's file
	## conventions.
	is_executable! : Path => Try(Bool, [PathErr(IOErr), ..])
	is_executable! = |path| map_file_result(Host.file_is_executable!(to_host_raw!(path)))

	## Check whether the current process can open the file for reading.
	is_readable! : Path => Try(Bool, [PathErr(IOErr), ..])
	is_readable! = |path| map_file_result(Host.file_is_readable!(to_host_raw!(path)))

	## Check whether the current process can open the file for writing. The file
	## is not modified.
	is_writable! : Path => Try(Bool, [PathErr(IOErr), ..])
	is_writable! = |path| map_file_result(Host.file_is_writable!(to_host_raw!(path)))

	## Return the last accessed time as a POSIX timestamp.
	time_accessed! : Path => Try(UnixTime.Timestamp, [PathErr(IOErr), ..])
	time_accessed! = |path|
		map_file_result(Host.file_time_accessed!(to_host_raw!(path))).map_ok(timestamp_from_host)

	## Return the last modified time as a POSIX timestamp.
	time_modified! : Path => Try(UnixTime.Timestamp, [PathErr(IOErr), ..])
	time_modified! = |path|
		map_file_result(Host.file_time_modified!(to_host_raw!(path))).map_ok(timestamp_from_host)

	## Return the creation time as a POSIX timestamp.
	time_created! : Path => Try(UnixTime.Timestamp, [PathErr(IOErr), ..])
	time_created! = |path|
		map_file_result(Host.file_time_created!(to_host_raw!(path))).map_ok(timestamp_from_host)

	## Create a hard link at `link` pointing to `original`.
	hard_link! : Path, Path => Try({}, [PathErr(IOErr), ..])
	hard_link! = |original, link|
		map_file_result(Host.file_hard_link!(to_host_raw!(original), to_host_raw!(link)))

	## Rename a file from `from` to `to`.
	rename! : Path, Path => Try({}, [PathErr(IOErr), ..])
	rename! = |from, to|
		map_file_result(Host.file_rename!(to_host_raw!(from), to_host_raw!(to)))

	## Create a directory at this path.
	create_dir! : Path => Try({}, [PathErr(IOErr), ..])
	create_dir! = |path| map_dir_result(Host.dir_create!(to_host_raw!(path)))

	## Create a directory and any missing parent directories at this path.
	create_all! : Path => Try({}, [PathErr(IOErr), ..])
	create_all! = |path| map_dir_result(Host.dir_create_all!(to_host_raw!(path)))

	## Delete an empty directory at this path.
	delete_empty! : Path => Try({}, [PathErr(IOErr), ..])
	delete_empty! = |path| map_dir_result(Host.dir_delete_empty!(to_host_raw!(path)))

	## Delete a directory and all contents at this path.
	delete_all! : Path => Try({}, [PathErr(IOErr), ..])
	delete_all! = |path| map_dir_result(Host.dir_delete_all!(to_host_raw!(path)))

	## List the entries in the directory at this path.
	list! : Path => Try(List(Path), [PathErr(IOErr), ..])
	list! = |path|
		match Host.dir_list!(to_host_raw!(path)) {
			Ok(paths) => Ok(paths.map(from_host_raw))
			Err(DirErr(err)) => Err(PathErr(err))
		}

	## Create a UTF-8 text path.
	utf8 : Str -> Path
	utf8 = |str| Utf8(str)

	## Create a UTF-8 text path from a quoted literal.
	from_quote : Str -> Try(Path, [BadQuotedBytes(Str)])
	from_quote = |str| Ok(Utf8(str))

	## Create a UTF-8 path from an interpolated string literal.
	## This performs textual concatenation; use [join] for path-component joining.
	from_interpolation : Str, Iter((Str, Str)) -> Path
	from_interpolation = |first, rest|
		Utf8(rest.fold(first, |acc, (interpolated, segment)| acc.concat(interpolated).concat(segment)))

	## Decode a path through a generic encoding.
	parser_for : _

	## Encode a path through a generic encoding.
	encoder_for : _

	## Create a Unix path from a Roc string by storing its UTF-8 bytes.
	unix : Str -> Path
	unix = |str| Unix(Str.to_utf8(str))

	## Create a Unix path from raw bytes without validating UTF-8.
	unix_bytes : List(U8) -> Path
	unix_bytes = |bytes| Unix(bytes)

	## Create a Windows path from a Roc string by storing its UTF-16 code units.
	windows : Str -> Path
	windows = |str| Windows(str_to_utf16(str))

	## Create a Windows path from raw UTF-16 code units.
	windows_u16s : List(U16) -> Path
	windows_u16s = |list| Windows(list)

	## Convert a path to a string if its raw representation is valid text.
	to_str : Path -> Try(Str, [InvalidStr(U64)])
	to_str = |path|
		match path {
			Utf8(str) => Ok(str)

			Unix(bytes) =>
				match Str.from_utf8(bytes) {
					Ok(str) => Ok(str)
					Err(BadUtf8({ index, problem: _ })) => Err(InvalidStr(index))
				}

			Windows(u16s) => utf16_to_str(u16s)
		}

	## Convert a path to a best-effort display string, replacing invalid text with
	## U+FFFD. This representation is lossy and must not be used for roundtripping.
	display : Path -> Str
	display = |path|
		match path {
			Utf8(str) => str
			Unix(bytes) => Str.from_utf8_lossy(bytes)
			Windows(u16s) => Str.from_utf8_lossy(utf16_to_utf8_lossy(u16s))
		}

	## Render a path for debugging without losing raw OS units.
	to_inspect : Path -> Str
	to_inspect = |path|
		match path {
			Utf8(str) => "Path.utf8(${Json.to_str(str)})"
			Unix(bytes) =>
				match Str.from_utf8(bytes) {
					Ok(str) => "Path.unix(${Json.to_str(str)})"
					Err(_) => "Path.unix_bytes(${Str.inspect(bytes)})"
				}
			Windows(u16s) =>
				match utf16_to_str(u16s) {
					Ok(str) => "Path.windows(${Json.to_str(str)})"
					Err(_) => "Path.windows_u16s(${Str.inspect(u16s)})"
				}
			}

	## Compare paths by their exact tagged representation.
	is_eq : Path, Path -> Bool
	is_eq = |left, right| to_raw(left) == to_raw(right)

	## Hash paths consistently with exact tagged equality.
	to_hash : Path, Hasher -> Hasher
	to_hash = |path, hasher|
		match to_raw(path) {
			Utf8(str) => Str.to_hash(str, Hasher.write_u8(hasher, 0))
			UnixBytes(bytes) => List.to_hash(bytes, Hasher.write_u8(hasher, 1))
			WindowsU16s(u16s) => List.to_hash(u16s, Hasher.write_u8(hasher, 2))
		}

	## Returns everything after the last directory separator.
	filename : Path -> Try(Path, [IsDirPath, EndsInDots])
	filename = |path|
		match path {
			Utf8(str) => {
				bytes = Str.to_utf8(str)

				if ends_with_u8(bytes, '/') {
					Err(IsDirPath)
				} else if ends_with_two_u8(bytes, '.', '.') {
					Err(EndsInDots)
				} else {
					match List.find_last_index(bytes, |byte| byte == '/') {
						Ok(last_sep_index) => Ok(Utf8(str_from_valid_utf8(after_index_u8(bytes, last_sep_index))))
						Err(NotFound) => Ok(path)
					}
				}
			}

			Unix(bytes) =>
				if ends_with_u8(bytes, '/') {
					Err(IsDirPath)
				} else if ends_with_two_u8(bytes, '.', '.') {
					Err(EndsInDots)
				} else {
					match List.find_last_index(bytes, |byte| byte == '/') {
						Ok(last_sep_index) => Ok(Unix(after_index_u8(bytes, last_sep_index)))
						Err(NotFound) => Ok(path)
					}
				}

			Windows(u16s) =>
				if ends_with_u16(u16s, '/') or ends_with_u16(u16s, '\\') {
					Err(IsDirPath)
				} else if ends_with_two_u16(u16s, '.', '.') {
					Err(EndsInDots)
				} else {
					match List.find_last_index(u16s, |u16| u16 == '/' or u16 == '\\') {
						Ok(last_sep_index) => Ok(Windows(after_index_u16(u16s, last_sep_index)))
						Err(NotFound) => Ok(path)
					}
				}
			}

	## Returns the filename extension without the leading dot.
	ext : Path -> Try(Path, [IsDirPath, EndsInDots])
	ext = |path|
		match filename(path) {
			Err(err) => Err(err)
			Ok(Utf8(str)) => Ok(Utf8(str_from_valid_utf8(ext_units_u8(Str.to_utf8(str)))))
			Ok(Unix(bytes)) => Ok(Unix(ext_units_u8(bytes)))
			Ok(Windows(u16s)) => Ok(Windows(ext_units_u16(u16s)))
		}

	## Adds a separator and a string component to the path.
	join : Path, Str -> Path
	join = |path, str|
		match path {
			Utf8(path_str) => Utf8(path_str.concat("/").concat(str))
			Unix(bytes) => Unix(bytes.append('/').concat(Str.to_utf8(str)))
			Windows(u16s) => Windows(u16s.append('\\').concat(str_to_utf16(str)))
		}

	## Expose the raw OS-specific representation.
	to_raw : Path -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
	to_raw = |path|
		match path {
			Utf8(str) => Utf8(str)
			Unix(bytes) => UnixBytes(bytes)
			Windows(u16s) => WindowsU16s(u16s)
		}

	## Build a path from the raw OS-specific representation.
	from_raw : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))] -> Path
	from_raw = |raw|
		match raw {
			Utf8(str) => Utf8(str)
			UnixBytes(bytes) => Unix(bytes)
			WindowsU16s(u16s) => Windows(u16s)
		}
}

to_host_raw! : Path => Host.RawPath
to_host_raw! = |path|
	match Path.to_raw(path) {
		Utf8(str) =>
			if Host.env_is_windows!("") {
				{ is_windows: Bool.True, unix_bytes: [], windows_u16s: str_to_utf16(str) }
			} else {
				{ is_windows: Bool.False, unix_bytes: Str.to_utf8(str), windows_u16s: [] }
			}
		UnixBytes(bytes) => { is_windows: Bool.False, unix_bytes: bytes, windows_u16s: [] }
		WindowsU16s(u16s) => { is_windows: Bool.True, unix_bytes: [], windows_u16s: u16s }
	}

from_host_raw : Host.RawPath -> Path
from_host_raw = |raw|
	if raw.is_windows {
		Path.windows_u16s(raw.windows_u16s)
	} else {
		Path.unix_bytes(raw.unix_bytes)
	}

map_file_result : Try(a, [FileErr(IOErr)]) -> Try(a, [PathErr(IOErr), ..])
map_file_result = |result|
	match result {
		Ok(value) => Ok(value)
		Err(FileErr(err)) => Err(PathErr(err))
	}

map_dir_result : Try(a, [DirErr(IOErr)]) -> Try(a, [PathErr(IOErr), ..])
map_dir_result = |result|
	match result {
		Ok(value) => Ok(value)
		Err(DirErr(err)) => Err(PathErr(err))
	}

str_from_valid_utf8 : List(U8) -> Str
str_from_valid_utf8 = |bytes|
	match Str.from_utf8(bytes) {
		Ok(str) => str
		Err(_) => {
			crash "A valid UTF-8 path contained invalid UTF-8 after ASCII path slicing."
		}
	}

str_to_utf16 : Str -> List(U16)
str_to_utf16 = |str| utf8_to_utf16(Str.to_utf8(str), [])

utf8_to_utf16 : List(U8), List(U16) -> List(U16)
utf8_to_utf16 = |remaining, out|
	match remaining {
		[] => out

		[byte, .. as rest] if byte < 0x80 =>
			utf8_to_utf16(rest, out.append(U8.to_u16(byte)))

		[byte1, byte2, .. as rest] if byte1 < 0xE0 => {
			top = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte1, 0x1F)), 6)
			bottom = U8.to_u32(U8.bitwise_and(byte2, 0x3F))
			code_point = U32.bitwise_or(top, bottom)

			utf8_to_utf16(rest, out.append(U32.to_u16_wrap(code_point)))
		}

		[byte1, byte2, byte3, .. as rest] if byte1 < 0xF0 => {
			top = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte1, 0x0F)), 12)
			middle = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte2, 0x3F)), 6)
			bottom = U8.to_u32(U8.bitwise_and(byte3, 0x3F))
			code_point = U32.bitwise_or(U32.bitwise_or(top, middle), bottom)

			utf8_to_utf16(rest, out.append(U32.to_u16_wrap(code_point)))
		}

		[byte1, byte2, byte3, byte4, .. as rest] => {
			top = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte1, 0x07)), 18)
			middle1 = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte2, 0x3F)), 12)
			middle2 = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte3, 0x3F)), 6)
			bottom = U8.to_u32(U8.bitwise_and(byte4, 0x3F))
			upper = U32.bitwise_or(U32.bitwise_or(top, middle1), middle2)
			code_point = U32.bitwise_or(upper, bottom)

			high = U32.to_u16_wrap(0xD800 + U32.shr_wrap(code_point - 0x10000, 10))
			low = U32.to_u16_wrap(0xDC00 + U32.bitwise_and(code_point - 0x10000, 0x3FF))

			utf8_to_utf16(rest, out.append(high).append(low))
		}

		_ => {
			crash "A Str contained invalid UTF-8. This should never happen."
		}
	}

utf16_to_str : List(U16) -> Try(Str, [InvalidStr(U64)])
utf16_to_str = |u16s|
	match utf16_to_utf8(u16s, [], 0) {
		Ok(bytes) =>
			match Str.from_utf8(bytes) {
				Ok(str) => Ok(str)
				Err(BadUtf8({ index, problem: _ })) => Err(InvalidStr(index))
			}

		Err(InvalidUtf16(index)) => Err(InvalidStr(index))
	}

utf16_to_utf8 : List(U16), List(U8), U64 -> Try(List(U8), [InvalidUtf16(U64)])
utf16_to_utf8 = |remaining, out, index|
	match remaining {
		[] => Ok(out)

		[high, low, .. as rest] if is_high_surrogate(high) and is_low_surrogate(low) => {
			high_bits = U32.shl_wrap(U16.to_u32(high) - 0xD800, 10)
			low_bits = U16.to_u32(low) - 0xDC00
			code_point = 0x10000 + high_bits + low_bits

			utf16_to_utf8(rest, append_code_point_utf8(out, code_point), index + 2)
		}

		[unit, ..] if is_surrogate(unit) => Err(InvalidUtf16(index))

		[unit, .. as rest] =>
			utf16_to_utf8(rest, append_code_point_utf8(out, U16.to_u32(unit)), index + 1)
		}

utf16_to_utf8_lossy : List(U16) -> List(U8)
utf16_to_utf8_lossy = |u16s| utf16_to_utf8_lossy_help(u16s, [])

utf16_to_utf8_lossy_help : List(U16), List(U8) -> List(U8)
utf16_to_utf8_lossy_help = |remaining, out|
	match remaining {
		[] => out

		[high, low, .. as rest] if is_high_surrogate(high) and is_low_surrogate(low) => {
			high_bits = U32.shl_wrap(U16.to_u32(high) - 0xD800, 10)
			low_bits = U16.to_u32(low) - 0xDC00
			code_point = 0x10000 + high_bits + low_bits

			utf16_to_utf8_lossy_help(rest, append_code_point_utf8(out, code_point))
		}

		[unit, .. as rest] if is_surrogate(unit) =>
			utf16_to_utf8_lossy_help(rest, append_code_point_utf8(out, 0xFFFD))

		[unit, .. as rest] =>
			utf16_to_utf8_lossy_help(rest, append_code_point_utf8(out, U16.to_u32(unit)))
		}

append_code_point_utf8 : List(U8), U32 -> List(U8)
append_code_point_utf8 = |out, code_point|
	if code_point < 0x80 {
		out.append(U32.to_u8_wrap(code_point))
	} else if code_point < 0x800 {
		out.append(U32.to_u8_wrap(0xC0 + U32.shr_wrap(code_point, 6)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(code_point, 0x3F)))
	} else if code_point < 0x10000 {
		out.append(U32.to_u8_wrap(0xE0 + U32.shr_wrap(code_point, 12)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(U32.shr_wrap(code_point, 6), 0x3F)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(code_point, 0x3F)))
	} else {
		out.append(U32.to_u8_wrap(0xF0 + U32.shr_wrap(code_point, 18)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(U32.shr_wrap(code_point, 12), 0x3F)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(U32.shr_wrap(code_point, 6), 0x3F)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(code_point, 0x3F)))
	}

is_high_surrogate : U16 -> Bool
is_high_surrogate = |unit| unit >= 0xD800 and unit <= 0xDBFF

is_low_surrogate : U16 -> Bool
is_low_surrogate = |unit| unit >= 0xDC00 and unit <= 0xDFFF

is_surrogate : U16 -> Bool
is_surrogate = |unit| unit >= 0xD800 and unit <= 0xDFFF

ends_with_u8 : List(U8), U8 -> Bool
ends_with_u8 = |list, suffix|
	match list {
		[.., last] => last == suffix
		[] => False
	}

ends_with_u16 : List(U16), U16 -> Bool
ends_with_u16 = |list, suffix|
	match list {
		[.., last] => last == suffix
		[] => False
	}

ends_with_two_u8 : List(U8), U8, U8 -> Bool
ends_with_two_u8 = |list, first_suffix, second_suffix|
	match list {
		[.., first, second] => first == first_suffix and second == second_suffix
		_ => False
	}

ends_with_two_u16 : List(U16), U16, U16 -> Bool
ends_with_two_u16 = |list, first_suffix, second_suffix|
	match list {
		[.., first, second] => first == first_suffix and second == second_suffix
		_ => False
	}

after_index_u8 : List(U8), U64 -> List(U8)
after_index_u8 = |list, index| {
	start = index + 1
	list.sublist({ start, len: list.len() - start })
}

after_index_u16 : List(U16), U64 -> List(U16)
after_index_u16 = |list, index| {
	start = index + 1
	list.sublist({ start, len: list.len() - start })
}

ext_units_u8 : List(U8) -> List(U8)
ext_units_u8 = |units|
	match List.find_first_index(units, |unit| unit == '.') {
		Err(NotFound) => []
		Ok(0) => {
			rest = units.drop_first(1)

			match List.find_first_index(rest, |unit| unit == '.') {
				Err(NotFound) => []
				Ok(dot_index) => after_index_u8(rest, dot_index)
			}
		}
		Ok(dot_index) => after_index_u8(units, dot_index)
	}

ext_units_u16 : List(U16) -> List(U16)
ext_units_u16 = |units|
	match List.find_first_index(units, |unit| unit == '.') {
		Err(NotFound) => []
		Ok(0) => {
			rest = units.drop_first(1)

			match List.find_first_index(rest, |unit| unit == '.') {
				Err(NotFound) => []
				Ok(dot_index) => after_index_u16(rest, dot_index)
			}
		}
		Ok(dot_index) => after_index_u16(units, dot_index)
	}

quoted_literal_path : Path
quoted_literal_path = "config.txt"

path_identity : Path -> Path
path_identity = |path| path

path_json_round_trips : Path -> Bool
path_json_round_trips = |path| {
	decoded : Try(Path, [InvalidJson(Str)])
	decoded = Json.parse(Json.to_str(path))

	match decoded {
		Ok(value) => value == path
		Err(_) => False
	}
}

## Constructors preserve Unix, Windows, and UTF-8 path representations.
expect Path.unix("abc") == Unix([97, 98, 99])

## Derived generic codecs roundtrip every path representation.
expect [
	Path.utf8("config.toml"),
	Path.unix_bytes([97, 255, 98]),
	Path.windows_u16s([0xD800, 97]),
].all(path_json_round_trips)

## Unix byte construction preserves every byte.
expect Path.unix_bytes([97, 98, 99]) == Unix([97, 98, 99])

## Windows text construction encodes UTF-16 units.
expect Path.windows("abc") == Windows([97, 98, 99])

## Windows unit construction preserves every unit.
expect Path.windows_u16s([97, 98, 99]) == Windows([97, 98, 99])

## UTF-8 construction preserves text.
expect Path.utf8("abc") == Utf8("abc")

## Quoted literals dispatch to UTF-8 paths through `from_quote`.
expect Path.from_quote("config.txt") == Ok(Path.utf8("config.txt"))

## Quoted path literals construct UTF-8 paths.
expect quoted_literal_path == Path.utf8("config.txt")

## Quoted arguments dispatch through the path literal hook.
expect path_identity("nested/config.txt") == Path.utf8("nested/config.txt")

## Interpolation creates a UTF-8 representation.
expect {
	directory = "config"
	path : Path
	path = "${directory}/app.toml"
	path == Path.utf8("config/app.toml")
}

## Raw conversion roundtrips every representation without validating raw OS data.
expect Path.to_raw(Path.unix_bytes([97, 255, 98])) == UnixBytes([97, 255, 98])

## Raw conversion preserves invalid Windows units.
expect Path.to_raw(Path.windows_u16s([0xD800, 97])) == WindowsU16s([0xD800, 97])

## Raw conversion preserves UTF-8 text.
expect Path.to_raw(Path.utf8("abc")) == Utf8("abc")

## Raw Unix bytes reconstruct a Unix path.
expect Path.from_raw(UnixBytes([97, 255, 98])) == Path.unix_bytes([97, 255, 98])

## Raw Windows units reconstruct a Windows path.
expect Path.from_raw(WindowsU16s([97, 98, 99])) == Path.windows("abc")

## Raw UTF-8 text reconstructs a UTF-8 path.
expect Path.from_raw(Utf8("abc")) == Path.utf8("abc")

## `to_str` succeeds for valid text and reports the first invalid raw unit.
expect Path.to_str(Path.unix("abc")) == Ok("abc")

## `to_str` reports the first invalid Unix byte.
expect Path.to_str(Path.unix_bytes([97, 255, 98])) == Err(InvalidStr(1))

## `to_str` decodes valid Windows text.
expect Path.to_str(Path.windows("abc")) == Ok("abc")

## `to_str` reports the first invalid Windows unit.
expect Path.to_str(Path.windows_u16s([0xD800])) == Err(InvalidStr(0))

## `to_str` returns UTF-8 paths unchanged.
expect Path.to_str(Path.utf8("abc")) == Ok("abc")

## `to_str` combines a valid UTF-16 surrogate pair.
expect Path.to_str(Path.windows_u16s([0xD83D, 0xDC26])) == Ok(Str.from_utf8_lossy([0xF0, 0x9F, 0x90, 0xA6]))

## `display` preserves valid text and replaces invalid raw units.
expect Path.display(Path.unix("abc")) == "abc"

## Unix display replaces invalid UTF-8.
expect Path.display(Path.unix_bytes([97, 255, 98])) == Str.from_utf8_lossy([97, 255, 98])

## Windows display preserves valid text.
expect Path.display(Path.windows("abc")) == "abc"

## Windows display replaces invalid UTF-16.
expect Path.display(Path.windows_u16s([0xD800, 97])) == Str.from_utf8_lossy([0xEF, 0xBF, 0xBD, 97])

## UTF-8 display preserves text.
expect Path.display(Path.utf8("abc")) == "abc"

## Inspection identifies the representation and preserves invalid raw units.
expect Str.inspect(Path.utf8("a\nb")) == "Path.utf8(\"a\\nb\")"

## Unix text inspection identifies its representation.
expect Str.inspect(Path.unix("abc")) == "Path.unix(\"abc\")"

## Unix byte inspection preserves invalid UTF-8.
expect Str.inspect(Path.unix_bytes([97, 255, 98])) == "Path.unix_bytes([97, 255, 98])"

## Windows text inspection identifies its representation.
expect Str.inspect(Path.windows("abc")) == "Path.windows(\"abc\")"

## Windows unit inspection preserves invalid UTF-16.
expect Str.inspect(Path.windows_u16s([0xD800, 97])) == "Path.windows_u16s([55296, 97])"

## Equality and hashing preserve representation identity.
expect Path.utf8("abc") != Path.unix("abc")

## Equal raw paths produce matching dictionary hashes.
expect Dict.single(Path.unix_bytes([97, 255]), "found").get(Path.unix_bytes([97, 255])) == Ok("found")

## `filename` returns everything after the last separator.
expect Path.filename(Path.unix("foo/bar.txt")) == Ok(Path.unix("bar.txt"))

## Unix filenames may omit an extension.
expect Path.filename(Path.unix("foo/bar")) == Ok(Path.unix("bar"))

## A bare Unix path is its own filename.
expect Path.filename(Path.unix("foo")) == Ok(Path.unix("foo"))

## An empty Unix path has an empty filename.
expect Path.filename(Path.unix("")) == Ok(Path.unix(""))

## Windows backslashes delimit filenames.
expect Path.filename(Path.windows("foo\\bar.txt")) == Ok(Path.windows("bar.txt"))

## Windows paths also accept forward-slash separators.
expect Path.filename(Path.windows("foo/bar.txt")) == Ok(Path.windows("bar.txt"))

## A bare Windows path is its own filename.
expect Path.filename(Path.windows("foo")) == Ok(Path.windows("foo"))

## An empty Windows path has an empty filename.
expect Path.filename(Path.windows("")) == Ok(Path.windows(""))

## UTF-8 paths use forward-slash separators.
expect Path.filename(Path.utf8("foo/bar.txt")) == Ok(Path.utf8("bar.txt"))

## A bare UTF-8 path is its own filename.
expect Path.filename(Path.utf8("foo")) == Ok(Path.utf8("foo"))

## An empty UTF-8 path has an empty filename.
expect Path.filename(Path.utf8("")) == Ok(Path.utf8(""))

## `filename` rejects directory paths and filenames ending in two dots.
expect Path.filename(Path.unix("foo/bar/")) == Err(IsDirPath)

## Unix filenames cannot end in two dots.
expect Path.filename(Path.unix("foo/bar..")) == Err(EndsInDots)

## Windows directory paths have no filename.
expect Path.filename(Path.windows("foo\\bar\\")) == Err(IsDirPath)

## Windows filenames cannot end in two dots.
expect Path.filename(Path.windows("foo/bar..")) == Err(EndsInDots)

## UTF-8 directory paths have no filename.
expect Path.filename(Path.utf8("foo/bar/")) == Err(IsDirPath)

## UTF-8 filenames cannot end in two dots.
expect Path.filename(Path.utf8("foo/bar..")) == Err(EndsInDots)

## `ext` returns the filename extension without the leading dot.
expect Path.ext(Path.unix("foo/bar.txt")) == Ok(Path.unix("txt"))

## A trailing Unix dot produces an empty extension.
expect Path.ext(Path.unix("foo/bar.")) == Ok(Path.unix(""))

## A dotted Unix filename returns text after the final dot.
expect Path.ext(Path.unix("foo/.bar.txt")) == Ok(Path.unix("txt"))

## A Unix filename without a dot has no extension.
expect Path.ext(Path.unix("foo/bar")) == Ok(Path.unix(""))

## A Unix dotfile without another dot has no extension.
expect Path.ext(Path.unix("foo/.bar")) == Ok(Path.unix(""))

## Unix extensions retain text after the first filename dot.
expect Path.ext(Path.unix("foo/bar.baz.txt")) == Ok(Path.unix("baz.txt"))

## Unix dotfile extensions retain text after the first filename dot.
expect Path.ext(Path.unix("foo/.bar.baz.txt")) == Ok(Path.unix("baz.txt"))

## An empty Unix path has no extension.
expect Path.ext(Path.unix("")) == Ok(Path.unix(""))

## Windows extensions use the filename after a backslash.
expect Path.ext(Path.windows("foo\\bar.txt")) == Ok(Path.windows("txt"))

## A Windows filename without a dot has no extension.
expect Path.ext(Path.windows("foo\\bar")) == Ok(Path.windows(""))

## An empty Windows path has no extension.
expect Path.ext(Path.windows("")) == Ok(Path.windows(""))

## UTF-8 extensions omit the leading dot.
expect Path.ext(Path.utf8("foo/bar.txt")) == Ok(Path.utf8("txt"))

## A UTF-8 dotfile without another dot has no extension.
expect Path.ext(Path.utf8("foo/.bar")) == Ok(Path.utf8(""))

## UTF-8 extensions retain text after the first filename dot.
expect Path.ext(Path.utf8("foo/bar.baz.txt")) == Ok(Path.utf8("baz.txt"))

## An empty UTF-8 path has no extension.
expect Path.ext(Path.utf8("")) == Ok(Path.utf8(""))

## `ext` forwards filename errors for directory paths and dot endings.
expect Path.ext(Path.unix("foo/bar/")) == Err(IsDirPath)

## Unix extension lookup rejects filenames ending in two dots.
expect Path.ext(Path.unix("foo/bar..")) == Err(EndsInDots)

## Windows extension lookup rejects directory paths.
expect Path.ext(Path.windows("foo\\bar\\")) == Err(IsDirPath)

## Windows extension lookup rejects filenames ending in two dots.
expect Path.ext(Path.windows("foo\\bar..")) == Err(EndsInDots)

## UTF-8 extension lookup rejects directory paths.
expect Path.ext(Path.utf8("foo/bar/")) == Err(IsDirPath)

## UTF-8 extension lookup rejects filenames ending in two dots.
expect Path.ext(Path.utf8("foo/bar..")) == Err(EndsInDots)

## Host path types map exhaustively to the public API.
expect path_type_from_host({ is_file: Bool.True, is_dir: Bool.False, is_sym_link: Bool.False }) == IsFile

## Host directories map to `IsDir`.
expect path_type_from_host({ is_file: Bool.False, is_dir: Bool.True, is_sym_link: Bool.False }) == IsDir

## Host symbolic links map to `IsSymLink`.
expect path_type_from_host({ is_file: Bool.False, is_dir: Bool.False, is_sym_link: Bool.True }) == IsSymLink

## Unknown host path types map to `IsOther`.
expect path_type_from_host({ is_file: Bool.False, is_dir: Bool.False, is_sym_link: Bool.False }) == IsOther

## `join` appends a representation-specific separator and text component.
expect Path.join(Path.unix("foo"), "bar") == Path.unix("foo/bar")

## Windows joins use backslash separators.
expect Path.join(Path.windows("foo"), "bar") == Path.windows("foo\\bar")

## UTF-8 joins use forward-slash separators.
expect Path.join(Path.utf8("foo"), "bar") == Path.utf8("foo/bar")
