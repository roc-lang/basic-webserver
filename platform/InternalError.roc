interface InternalError
    exposes [
        InternalError,
        InternalDirReadErr,
        InternalDirDeleteErr,
    ]
    imports [Path.{ Path }]

InternalError : [
    IOError Str,
    EOF,
]

InternalDirReadErr : [DirReadErr Path Str]

InternalDirDeleteErr : [DirDeleteErr Path Str]
