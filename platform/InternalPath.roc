import Host
import Path exposing [Path]

InternalPath := [].{
	from_host_raw : Host.RawPath -> Path
	from_host_raw = |raw_path|
		if raw_path.is_windows {
			Path.windows_u16s(raw_path.windows_u16s)
		} else {
			Path.unix_bytes(raw_path.unix_bytes)
		}

	to_host_raw! : Path => Host.RawPath
	to_host_raw! = |path|
		match Path.to_raw(path) {
			Utf8(str) =>
				if Host.env_is_windows!("") {
					{
						is_windows: Bool.True,
						unix_bytes: [],
						windows_u16s: match Path.to_raw(Path.windows(str)) {
							WindowsU16s(u16s) => u16s
							_ => []
						},
					}
				} else {
					{
						is_windows: Bool.False,
						unix_bytes: Str.to_utf8(str),
						windows_u16s: [],
					}
				}
			UnixBytes(bytes) => {
				is_windows: Bool.False,
				unix_bytes: bytes,
				windows_u16s: [],
			}
			WindowsU16s(u16s) => {
				is_windows: Bool.True,
				unix_bytes: [],
				windows_u16s: u16s,
			}
		}
}
