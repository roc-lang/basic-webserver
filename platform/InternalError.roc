interface InternalError
    exposes [InternalError, CacheError, InternalDirReadErr, InternalDirDeleteErr]
    imports [Path.{ Path }]

InternalError : [
    IOError Str,
    EOF,
]

CacheError : [NotFound]

InternalDirReadErr : [DirReadErr Path Str]

InternalDirDeleteErr : [DirDeleteErr Path Str]