module [
    Value,
    Code,
    Error,
    Binding,
    prepare,
    bind,
    prepareAndBind,
    execute,
    errToStr,
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
    succeed,
    with,
    apply,
]

import InternalTask
import Task exposing [Task]
import InternalSQL
import Effect

Value : InternalSQL.SQLiteValue
Code : InternalSQL.SQLiteErrCode
Error : [SQLError Code Str]
Binding : InternalSQL.SQLiteBindings
Stmt := Box {}

prepareAndBind :
    {
        path : Str,
        query : Str,
        bindings : List Binding,
    }
    -> Task Stmt Error
prepareAndBind = \{ path, query, bindings } ->
    stmt = prepare! { path, query }
    bind! stmt bindings
    Task.ok stmt

prepare :
    {
        path : Str,
        query : Str,
    }
    -> Task Stmt Error
prepare = \{ path, query } ->
    Effect.sqlitePrepare path query
    |> InternalTask.fromEffect
    |> Task.map @Stmt
    |> Task.mapErr internalToExternalError

bind : Stmt, List Binding -> Task {} Error
bind = \@Stmt stmt, bindings ->
    Effect.sqliteBind stmt bindings
    |> InternalTask.fromEffect
    |> Task.mapErr internalToExternalError

columnIndex : Stmt, Str -> Task U64 [FieldNotFound Str]
columnIndex = \@Stmt stmt, name ->
    Effect.sqliteColumnIndex stmt name
    |> InternalTask.fromEffect
    |> Task.mapErr \{} -> FieldNotFound name

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

DecodeErr err : [FieldNotFound Str, SQLError Code Str]err
DecodeCont a err : {} -> Task a (DecodeErr err)

Decode a err :=
    Stmt
    ->
    Task
        (DecodeCont a err)
        (DecodeErr err)

execute : Stmt, Decode a err -> Task (List a) (DecodeErr err)
execute = \stmt, @Decode getDecode ->
    reset! stmt
    fn = getDecode! stmt
    decodeRows stmt fn

decodeRows : Stmt, ({} -> Task a (DecodeErr err)) -> Task (List a) (DecodeErr err)
decodeRows = \stmt, fn ->
    Task.loop [] \out ->
        when step! stmt is
            Done ->
                Task.ok (Done out)

            Row ->
                row = fn! {}

                List.append out row
                |> Step
                |> Task.ok

decoder = \fn -> \name ->
        stmt <- @Decode

        index = columnIndex! stmt name

        {} <- Task.ok

        val = columnValue! stmt index

        fn val |> Task.fromResult

taggedValue = decoder \val ->
    Ok val

str = decoder \val ->
    when val is
        Str s -> Ok s
        _ -> Err (UnexpectedType val)

bytes = decoder \val ->
    when val is
        Bytes b -> Ok b
        _ -> Err (UnexpectedType val)

intDecoder = \cast ->
    decoder \val ->
        when val is
            Integer i -> cast i |> Result.mapErr FailedToDecodeInteger
            _ -> Err (UnexpectedType val)

i64 = intDecoder Ok

i32 = intDecoder Num.toI32Checked

i16 = intDecoder Num.toI16Checked

i8 = intDecoder Num.toI8Checked

u64 = intDecoder Num.toU64Checked

u32 = intDecoder Num.toU32Checked

u16 = intDecoder Num.toU16Checked

u8 = intDecoder Num.toU8Checked

realDecoder = \cast ->
    decoder \val ->
        when val is
            Real r -> cast r |> Result.mapErr FailedToDecodeReal
            _ -> Err (UnexpectedType val)

f64 = realDecoder Ok

f32 = realDecoder (\x -> Num.toF32 x |> Ok)

# TODO: Mising Num.toDec and Num.toDecChecked
# dec = realDecoder Ok

map2 = \@Decode a, @Decode b, cb ->
    stmt <- @Decode

    decodeA = a! stmt
    decodeB = b! stmt

    {} <- Task.ok

    valueA = decodeA! {}
    valueB = decodeB! {}

    Task.ok (cb valueA valueB)

succeed = \value ->
    @Decode \_ -> Task.ok \_ -> Task.ok value

with = \a, b -> map2 a b (\fn, val -> fn val)

apply = \a -> \fn -> with fn a

internalToExternalError : InternalSQL.SQLiteError -> Error
internalToExternalError = \{ code, message } ->
    SQLError (codeFromI64 code) message

codeFromI64 : I64 -> InternalSQL.SQLiteErrCode
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
        crash "unsupported SQLite error code $(Num.toStr code)"

errToStr : Error -> Str
errToStr = \err ->
    (code, msg2) =
        when err is
            SQLError c m -> (c, m)

    msg1 =
        when code is
            ERROR -> "ERROR: SQL error or missing database"
            INTERNAL -> "INTERNAL: Internal logic error in SQLite"
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

