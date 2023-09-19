interface Request exposes [Request] imports [Header.{ Header }]

Request : { method : Str, url : Str, headers : List Header }
