interface Response exposes [Response] imports [Header.{ Header }]

Response : { status : U16, headers : List Header, body: List U8 }
