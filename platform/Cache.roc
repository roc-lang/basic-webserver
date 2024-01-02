interface Cache
    exposes [get,set]
    imports [Effect, InternalTask, Task.{ Task }]

get : U64 -> Task (List U8) [NotFound]
get = \key ->
    Effect.getKV key
    |> InternalTask.fromEffect


set : U64, List U8 -> Task {} *
set = \key, value ->
    Effect.setKV key value
    |> Effect.map Ok
    |> InternalTask.fromEffect