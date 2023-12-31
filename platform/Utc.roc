interface Utc
    exposes [
        Utc,
        now,
        toMillisSinceEpoch,
        fromMillisSinceEpoch,
        toNanosSinceEpoch,
        fromNanosSinceEpoch,
        deltaAsMillis,
        deltaAsNanos,
        toIso8601Str,
    ]
    imports [
        Effect, 
        InternalTask, 
        InternalDateTime,
        Task.{ Task },
    ]

## Stores a timestamp as nanoseconds since UNIX EPOCH
Utc := U128

## Duration since UNIX EPOCH
now : Task Utc *
now =
    Effect.posixTime
    |> Effect.map @Utc
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Convert Utc timestamp to ISO 8601 string
## Example: 2023-11-14T23:39:39Z
toIso8601Str : Utc -> Str
toIso8601Str = \@Utc nanos ->
    nanos
    |> Num.divTrunc nanosPerMilli
    |> InternalDateTime.epochMillisToDateTime 
    |> InternalDateTime.toIso8601Str

# Constant number of nanoseconds in a millisecond
nanosPerMilli = 1_000_000

## Convert Utc timestamp to milliseconds
toMillisSinceEpoch : Utc -> U128
toMillisSinceEpoch = \@Utc nanos ->
    nanos * nanosPerMilli

## Convert milliseconds to Utc timestamp
fromMillisSinceEpoch : U128 -> Utc
fromMillisSinceEpoch = \millis ->
    @Utc (millis * nanosPerMilli)

## Convert Utc timestamp to nanoseconds
toNanosSinceEpoch : Utc -> U128
toNanosSinceEpoch = \@Utc nanos ->
    nanos

## Convert nanoseconds to Utc timestamp
fromNanosSinceEpoch : U128 -> Utc
fromNanosSinceEpoch = @Utc

## Calculate milliseconds between two Utc timestamps
deltaAsMillis : Utc, Utc -> U128
deltaAsMillis = \@Utc first, @Utc second ->
    (Num.absDiff first second) // nanosPerMilli

## Calculate nanoseconds between two Utc timestamps
deltaAsNanos : Utc, Utc -> U128
deltaAsNanos = \@Utc first, @Utc second ->
    Num.absDiff first second
