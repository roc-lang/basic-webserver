interface Request exposes [Request, Method] imports [Header.{ Header }]

Method : [GET, POST, HEAD, DELETE, PUT, OPTIONS]

Request : { method : Method, url : Str, headers : List Header, body: List U8 }
