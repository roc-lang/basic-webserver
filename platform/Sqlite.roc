module [
    Value,
    Code,
    Error,
    Binding,
    query,
    queryExactlyOne,
    execute,
    errToStr,
    decodeRecord,
    taggedValue,
    str,
    bytes,
    i64,
    i32,
    i16,
    i8,
    u64,
    u32,
    u16,
    u8,
    f64,
    f32,
    Nullable,
    nullableStr,
    nullableBytes,
    nullableI64,
    nullableI32,
    nullableI16,
    nullableI8,
    nullableU64,
    nullableU32,
    nullableU16,
    nullableU8,
    nullableF64,
    nullableF32,
]

import InternalTask
import Task exposing [Task]
import InternalSql
import Effect

Value : InternalSql.SqliteValue
Code : InternalSql.SqliteErrCode
Error : [SqlError Code Str]
Binding : InternalSql.SqliteBindings
Stmt := Box {}

prepareAndBind :
    {
        path : Str,
        query : Str,
        bindings : List Binding,
    }
    -> Task Stmt Error
prepareAndBind = \{ path, query: q, bindings } ->
    stmt = prepare! { path, query: q }
    bind! stmt bindings
    Task.ok stmt

prepare :
    {
        path : Str,
        query : Str,
    }
    -> Task Stmt Error
prepare = \{ path, query: q } ->
    Effect.sqlitePrepare path q
    |> InternalTask.fromEffect
    |> Task.map @Stmt
    |> Task.mapErr internalToExternalError

bind : Stmt, List Binding -> Task {} Error
bind = \@Stmt stmt, bindings ->
    Effect.sqliteBind stmt bindings
    |> InternalTask.fromEffect
    |> Task.mapErr internalToExternalError

columns : Stmt -> Task (List Str) []
columns = \@Stmt stmt ->
    Effect.sqliteColumns stmt
    |> Effect.map Ok
    |> InternalTask.fromEffect

columnValue : Stmt, U64 -> Task Value Error
columnValue = \@Stmt stmt, i ->
    Effect.sqliteColumnValue stmt i
    |> InternalTask.fromEffect
    |> Task.mapErr internalToExternalError

step : Stmt -> Task [Row, Done] Error
step = \@Stmt stmt ->
    Effect.sqliteStep stmt
    |> InternalTask.fromEffect
    |> Task.mapErr internalToExternalError

reset : Stmt -> Task {} Error
reset = \@Stmt stmt ->
    Effect.sqliteReset stmt
    |> InternalTask.fromEffect
    |> Task.mapErr internalToExternalError

execute :
    {
        path : Str,
        query : Str,
        bindings : List Binding,
    }
    -> Task {} [SqlError Code Str, UnhandledRows]
execute = \{ path, query: q, bindings } ->
    stmt = prepareAndBind! { path, query: q, bindings }
    res = step stmt |> Task.result!
    reset! stmt
    when res is
        Ok Done ->
            Task.ok {}

        Ok Row ->
            Task.err UnhandledRows

        Err e ->
            Task.err e

query :
    {
        path : Str,
        query : Str,
        bindings : List Binding,
        rows : SqlDecode a err,
    }
    -> Task (List a) (SqlDecodeErr err)
query = \{ path, query: q, bindings, rows: decode } ->
    stmt = prepareAndBind! { path, query: q, bindings }
    res = decodeRows stmt decode |> Task.result!
    reset! stmt
    Task.fromResult res

queryExactlyOne :
    {
        path : Str,
        query : Str,
        bindings : List Binding,
        row : SqlDecode a (RowCountErr err),
    }
    -> Task a (SqlDecodeErr (RowCountErr err))
queryExactlyOne = \{ path, query: q, bindings, row: decode } ->
    stmt = prepareAndBind! { path, query: q, bindings }
    res = decodeExactlyOneRow stmt decode |> Task.result!
    reset! stmt
    Task.fromResult res

SqlDecodeErr err : [FieldNotFound Str, SqlError Code Str]err
SqlDecode a err := List Str -> (Stmt -> Task a (SqlDecodeErr err))

decodeRecord : SqlDecode a err, SqlDecode b err, (a, b -> c) -> SqlDecode c err
decodeRecord = \@SqlDecode genFirst, @SqlDecode genSecond, mapper ->
    cols <- @SqlDecode
    decodeFirst = genFirst cols
    decodeSecond = genSecond cols

    \stmt ->
        first = decodeFirst! stmt
        second = decodeSecond! stmt
        Task.ok (mapper first second)

RowCountErr err : [NoRowsReturned, TooManyRowsReturned]err
decodeExactlyOneRow : Stmt, SqlDecode a (RowCountErr err) -> Task a (SqlDecodeErr (RowCountErr err))
decodeExactlyOneRow = \stmt, @SqlDecode genDecode ->
    cols = columns! stmt
    decodeRow = genDecode cols

    when step! stmt is
        Row ->
            row = decodeRow! stmt
            when step! stmt is
                Done ->
                    Task.ok row

                Row ->
                    Task.err TooManyRowsReturned

        Done ->
            Task.err NoRowsReturned

decodeRows : Stmt, SqlDecode a err -> Task (List a) (SqlDecodeErr err)
decodeRows = \stmt, @SqlDecode genDecode ->
    cols = columns! stmt
    decodeRow = genDecode cols
    Task.loop [] \out ->
        when step! stmt is
            Done ->
                Task.ok (Done out)

            Row ->
                row = decodeRow! stmt

                List.append out row
                |> Step
                |> Task.ok

decoder : (Value -> Result a (SqlDecodeErr err)) -> (Str -> SqlDecode a err)
decoder = \fn -> \name ->
        cols <- @SqlDecode

        found = List.findFirstIndex cols \x -> x == name
        when found is
            Ok index ->
                \stmt ->
                    columnValue! stmt index
                        |> fn
                        |> Task.fromResult

            Err NotFound ->
                \_ ->
                    Task.err (FieldNotFound name)

taggedValue : Str -> SqlDecode Value []
taggedValue = decoder \val ->
    Ok val

str : Str -> SqlDecode Str [UnexpectedType Value]
str = decoder \val ->
    when val is
        String s -> Ok s
        _ -> Err (UnexpectedType val)

bytes : Str -> SqlDecode (List U8) [UnexpectedType Value]
bytes = decoder \val ->
    when val is
        Bytes b -> Ok b
        _ -> Err (UnexpectedType val)

intDecoder : (I64 -> Result a err) -> (Str -> SqlDecode a [UnexpectedType Value, FailedToDecodeInteger err])
intDecoder = \cast ->
    decoder \val ->
        when val is
            Integer i -> cast i |> Result.mapErr FailedToDecodeInteger
            _ -> Err (UnexpectedType val)

i64 : Str -> SqlDecode I64 [UnexpectedType Value, FailedToDecodeInteger []]
i64 = intDecoder Ok

i32 : Str -> SqlDecode I32 [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
i32 = intDecoder Num.toI32Checked

i16 : Str -> SqlDecode I16 [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
i16 = intDecoder Num.toI16Checked

i8 : Str -> SqlDecode I8 [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
i8 = intDecoder Num.toI8Checked

u64 : Str -> SqlDecode U64 [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
u64 = intDecoder Num.toU64Checked

u32 : Str -> SqlDecode U32 [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
u32 = intDecoder Num.toU32Checked

u16 : Str -> SqlDecode U16 [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
u16 = intDecoder Num.toU16Checked

u8 : Str -> SqlDecode U8 [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
u8 = intDecoder Num.toU8Checked

realDecoder : (F64 -> Result a err) -> (Str -> SqlDecode a [UnexpectedType Value, FailedToDecodeReal err])
realDecoder = \cast ->
    decoder \val ->
        when val is
            Real r -> cast r |> Result.mapErr FailedToDecodeReal
            _ -> Err (UnexpectedType val)

f64 : Str -> SqlDecode F64 [UnexpectedType Value, FailedToDecodeReal []]
f64 = realDecoder Ok

f32 : Str -> SqlDecode F32 [UnexpectedType Value, FailedToDecodeReal []]
f32 = realDecoder (\x -> Num.toF32 x |> Ok)

# TODO: Mising Num.toDec and Num.toDecChecked
# dec = realSqlDecoder Ok

# These are the same decoders as above but Nullable.
# If the sqlite field is `Null`, they will return `Null`.

Nullable a : [NotNull a, Null]

nullableStr : Str -> SqlDecode (Nullable Str) [UnexpectedType Value, FailedToDecodeReal []]
nullableStr = decoder \val ->
    when val is
        String s -> Ok (NotNull s)
        Null -> Ok Null
        _ -> Err (UnexpectedType val)

nullableBytes : Str -> SqlDecode (Nullable (List U8)) [UnexpectedType Value]
nullableBytes = decoder \val ->
    when val is
        Bytes b -> Ok (NotNull b)
        Null -> Ok Null
        _ -> Err (UnexpectedType val)

nullableIntDecoder : (I64 -> Result a err) -> (Str -> SqlDecode (Nullable a) [UnexpectedType Value, FailedToDecodeInteger err])
nullableIntDecoder = \cast ->
    decoder \val ->
        when val is
            Integer i -> cast i |> Result.map NotNull |> Result.mapErr FailedToDecodeInteger
            Null -> Ok Null
            _ -> Err (UnexpectedType val)

nullableI64 : Str -> SqlDecode (Nullable I64) [UnexpectedType Value, FailedToDecodeInteger []]
nullableI64 = nullableIntDecoder Ok

nullableI32 : Str -> SqlDecode (Nullable I32) [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
nullableI32 = nullableIntDecoder Num.toI32Checked

nullableI16 : Str -> SqlDecode (Nullable I16) [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
nullableI16 = nullableIntDecoder Num.toI16Checked

nullableI8 : Str -> SqlDecode (Nullable I8) [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
nullableI8 = nullableIntDecoder Num.toI8Checked

nullableU64 : Str -> SqlDecode (Nullable U64) [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
nullableU64 = nullableIntDecoder Num.toU64Checked

nullableU32 : Str -> SqlDecode (Nullable U32) [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
nullableU32 = nullableIntDecoder Num.toU32Checked

nullableU16 : Str -> SqlDecode (Nullable U16) [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
nullableU16 = nullableIntDecoder Num.toU16Checked

nullableU8 : Str -> SqlDecode (Nullable U8) [UnexpectedType Value, FailedToDecodeInteger [OutOfBounds]]
nullableU8 = nullableIntDecoder Num.toU8Checked

nullableRealDecoder : (F64 -> Result a err) -> (Str -> SqlDecode (Nullable a) [UnexpectedType Value, FailedToDecodeReal err])
nullableRealDecoder = \cast ->
    decoder \val ->
        when val is
            Real r -> cast r |> Result.map NotNull |> Result.mapErr FailedToDecodeReal
            Null -> Ok Null
            _ -> Err (UnexpectedType val)

nullableF64 : Str -> SqlDecode (Nullable F64) [UnexpectedType Value, FailedToDecodeReal []]
nullableF64 = nullableRealDecoder Ok

nullableF32 : Str -> SqlDecode (Nullable F32) [UnexpectedType Value, FailedToDecodeReal []]
nullableF32 = nullableRealDecoder (\x -> Num.toF32 x |> Ok)

# TODO: Mising Num.toDec and Num.toDecChecked
# nullableDec = nullableRealDecoder Ok

internalToExternalError : InternalSql.SqliteError -> Error
internalToExternalError = \{ code, message } ->
    SqlError (codeFromI64 code) message

codeFromI64 : I64 -> InternalSql.SqliteErrCode
codeFromI64 = \code ->
    if code == 1 || code == 0 then
        ERROR
    else if code == 2 then
        INTERNAL
    else if code == 3 then
        PERM
    else if code == 4 then
        ABORT
    else if code == 5 then
        BUSY
    else if code == 6 then
        LOCKED
    else if code == 7 then
        NOMEM
    else if code == 8 then
        READONLY
    else if code == 9 then
        INTERRUPT
    else if code == 10 then
        IOERR
    else if code == 11 then
        CORRUPT
    else if code == 12 then
        NOTFOUND
    else if code == 13 then
        FULL
    else if code == 14 then
        CANTOPEN
    else if code == 15 then
        PROTOCOL
    else if code == 16 then
        EMPTY
    else if code == 17 then
        SCHEMA
    else if code == 18 then
        TOOBIG
    else if code == 19 then
        CONSTRAINT
    else if code == 20 then
        MISMATCH
    else if code == 21 then
        MISUSE
    else if code == 22 then
        NOLFS
    else if code == 23 then
        AUTH
    else if code == 24 then
        FORMAT
    else if code == 25 then
        RANGE
    else if code == 26 then
        NOTADB
    else if code == 27 then
        NOTICE
    else if code == 28 then
        WARNING
    else if code == 100 then
        ROW
    else if code == 101 then
        DONE
    else
        crash "unsupported Sqlite error code $(Num.toStr code)"

errToStr : Error -> Str
errToStr = \err ->
    (SqlError code msg2) = err

    msg1 =
        when code is
            ERROR -> "ERROR: Sql error or missing database"
            INTERNAL -> "INTERNAL: Internal logic error in Sqlite"
            PERM -> "PERM: Access permission denied"
            ABORT -> "ABORT: Callback routine requested an abort"
            BUSY -> "BUSY: The database file is locked"
            LOCKED -> "LOCKED: A table in the database is locked"
            NOMEM -> "NOMEM: A malloc() failed"
            READONLY -> "READONLY: Attempt to write a readonly database"
            INTERRUPT -> "INTERRUPT: Operation terminated by sqlite3_interrupt("
            IOERR -> "IOERR: Some kind of disk I/O error occurred"
            CORRUPT -> "CORRUPT: The database disk image is malformed"
            NOTFOUND -> "NOTFOUND: Unknown opcode in sqlite3_file_control()"
            FULL -> "FULL: Insertion failed because database is full"
            CANTOPEN -> "CANTOPEN: Unable to open the database file"
            PROTOCOL -> "PROTOCOL: Database lock protocol error"
            EMPTY -> "EMPTY: Database is empty"
            SCHEMA -> "SCHEMA: The database schema changed"
            TOOBIG -> "TOOBIG: String or BLOB exceeds size limit"
            CONSTRAINT -> "CONSTRAINT: Abort due to constraint violation"
            MISMATCH -> "MISMATCH: Data type mismatch"
            MISUSE -> "MISUSE: Library used incorrectly"
            NOLFS -> "NOLFS: Uses OS features not supported on host"
            AUTH -> "AUTH: Authorization denied"
            FORMAT -> "FORMAT: Auxiliary database format error"
            RANGE -> "RANGE: 2nd parameter to sqlite3_bind out of range"
            NOTADB -> "NOTADB: File opened that is not a database file"
            NOTICE -> "NOTICE: Notifications from sqlite3_log()"
            WARNING -> "WARNING: Warnings from sqlite3_log()"
            ROW -> "ROW: sqlite3_step() has another row ready"
            DONE -> "DONE: sqlite3_step() has finished executing"

    "$(msg1) - $(msg2)"

