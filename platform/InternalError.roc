module [
    InternalError,
    InternalDirReadErr,
    InternalDirDeleteErr,
]

import Path exposing [Path]

InternalError : [
    IOError Str,
    EOF,
]

InternalDirReadErr : [DirReadErr Path Str]

InternalDirDeleteErr : [DirDeleteErr Path Str]
