import Host
import path.Path as PathPkg

InternalPath := [].{
    from_host_raw : Host.RawPath -> PathPkg.Path
    from_host_raw = |raw_path|
        if raw_path.is_windows {
            PathPkg.windows_u16s(raw_path.windows_u16s)
        } else {
            PathPkg.unix_bytes(raw_path.unix_bytes)
        }

    to_host_raw : PathPkg.Path -> Host.RawPath
    to_host_raw = |path|
        match PathPkg.to_raw(path) {
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
