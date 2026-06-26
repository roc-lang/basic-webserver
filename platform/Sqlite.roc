import InternalSqlite

# Porting notes for the new (zig) compiler: the decoder combinator API is written
# with fully-literal nested lambdas (`|name| |cols| |stmt| ...`) and relies on
# structural type inference. This is deliberate — the current compiler (a) treats
# an associated member whose body returns a function via a non-lambda expression as
# a hosted declaration, and (b) does not unify an associated `:` type alias (e.g.
# `Value`) with the structural tag union it aliases when used as a function
# parameter, nor support open tag-union extension (`[Tag]ext`) in annotations. So
# the decoders are left unannotated and all decoder errors live in one closed set
# of tags (see DecodeErr below for the documented shape).
Sqlite := [].{
    ## Represents a prepared statement that can be executed many times.
    Stmt :: Box(U64)

    # ---- Host functions (the FFI boundary) -------------------------------------

    host_prepare! : Str, Str => Try(Stmt, InternalSqlite.SqliteError)

    host_bind! : Stmt, List(InternalSqlite.SqliteBindings) => Try({}, InternalSqlite.SqliteError)

    host_columns! : Stmt => List(Str)

    host_column_value! : Stmt, U64 => Try(InternalSqlite.SqliteValue, InternalSqlite.SqliteError)

    # Returns Bool.True for SQLITE_ROW, Bool.False for SQLITE_DONE (the glue
    # generator mishandles a bare `[Row, Done]` enum at the host boundary).
    host_step! : Stmt => Try(Bool, InternalSqlite.SqliteError)

    host_reset! : Stmt => Try({}, InternalSqlite.SqliteError)

    ## Represents various error codes that can be returned by Sqlite.
    ErrCode : [
        Error,
        Internal,
        Perm,
        Abort,
        Busy,
        Locked,
        NoMem,
        ReadOnly,
        Interrupt,
        IOErr,
        Corrupt,
        NotFound,
        Full,
        CanNotOpen,
        Protocol,
        Empty,
        Schema,
        TooBig,
        Constraint,
        Mismatch,
        Misuse,
        NoLFS,
        AuthDenied,
        Format,
        OutOfRange,
        NotADatabase,
        Notice,
        Warning,
        Row,
        Done,
        Unknown(I64),
    ]

    ## Documented shape of the errors a decoder can produce (the decoders below are
    ## left unannotated and infer a subset of these structurally):
    ## ```
    ## [
    ##     NoSuchField(Str),
    ##     SqliteErr(ErrCode, Str),
    ##     UnexpectedType([Integer, Real, String, Bytes, Null]),
    ##     FailedToDecodeInteger,
    ##     FailedToDecodeReal,
    ##     IntOutOfBounds,
    ##     NoRowsReturned,
    ##     TooManyRowsReturned,
    ## ]
    ## ```
    DecodeErr : [NoSuchField(Str), SqliteErr(ErrCode, Str)]

    # ---- Statement lifecycle ---------------------------------------------------

    ## Prepare a [Stmt] for execution at a later time.
    prepare! = |{ path, query: q }|
        Sqlite.host_prepare!(path, q)
            .map_err(|{ code, message }| SqliteErr(code_from_i64(code), message))

    ## Bind named parameters to a prepared statement.
    bind! = |stmt, bindings|
        Sqlite.host_bind!(stmt, bindings)
            .map_err(|{ code, message }| SqliteErr(code_from_i64(code), message))

    ## Return the column names for a prepared statement.
    columns! = |stmt|
        Sqlite.host_columns!(stmt)

    ## Read the value of a column (by index) from the current row.
    column_value! = |stmt, i|
        Sqlite.host_column_value!(stmt, i)
            .map_err(|{ code, message }| SqliteErr(code_from_i64(code), message))

    ## Advance a prepared statement. Returns `Row` if a row is available, `Done` otherwise.
    step! = |stmt|
        match Sqlite.host_step!(stmt) {
            Ok(has_row) => if has_row { Ok(Row) } else { Ok(Done) }
            Err({ code, message }) => Err(SqliteErr(code_from_i64(code), message))
        }

    ## Reset a prepared statement back to its initial state, ready to be re-executed.
    reset! = |stmt|
        Sqlite.host_reset!(stmt)
            .map_err(|{ code, message }| SqliteErr(code_from_i64(code), message))

    ## Execute a SQL statement that **doesn't return any rows** (INSERT/UPDATE/DELETE).
    execute! = |{ path, query: q, bindings }| {
        stmt = prepare!({ path, query: q })?
        execute_prepared!({ stmt, bindings })
    }

    ## Execute a prepared SQL statement that **doesn't return any rows**.
    execute_prepared! = |{ stmt, bindings }| {
        bind!(stmt, bindings)?
        res = step!(stmt)
        reset!(stmt)?
        match res {
            Ok(Done) => Ok({})
            Ok(Row) => Err(RowsReturnedUseQueryInstead)
            Err(e) => Err(e)
        }
    }

    ## Execute a SQL query and decode exactly one row into a value.
    query! = |{ path, query: q, bindings, row }| {
        stmt = prepare!({ path, query: q })?
        query_prepared!({ stmt, bindings, row })
    }

    ## Execute a prepared SQL query and decode exactly one row into a value.
    query_prepared! = |{ stmt, bindings, row: decode }| {
        bind!(stmt, bindings)?
        res = decode_exactly_one_row!(stmt, decode)
        reset!(stmt)?
        res
    }

    ## Execute a SQL query and decode multiple rows into a list of values.
    query_many! = |{ path, query: q, bindings, rows }| {
        stmt = prepare!({ path, query: q })?
        query_many_prepared!({ stmt, bindings, rows })
    }

    ## Execute a prepared SQL query and decode multiple rows into a list of values.
    query_many_prepared! = |{ stmt, bindings, rows: decode }| {
        bind!(stmt, bindings)?
        res = decode_rows!(stmt, decode)
        reset!(stmt)?
        res
    }

    # internal use only
    decode_exactly_one_row! = |stmt, gen_decode| {
        cols = columns!(stmt)
        decode_row! = gen_decode(cols)
        match step!(stmt)? {
            Row => {
                row = decode_row!(stmt)?
                match step!(stmt)? {
                    Done => Ok(row)
                    Row => Err(TooManyRowsReturned)
                }
            }
            Done => Err(NoRowsReturned)
        }
    }

    # internal use only
    decode_rows! = |stmt, gen_decode| {
        cols = columns!(stmt)
        decode_row! = gen_decode(cols)
        helper! = |out|
            match step!(stmt)? {
                Done => Ok(out)
                Row => {
                    row = decode_row!(stmt)?
                    helper!(out.append(row))
                }
            }
        helper!([])
    }

    # ---- Row decoding combinators ----------------------------------------------

    ## Decode a Sqlite row into a record by combining two decoders.
    decode_record = |gen_first, gen_second, mapper|
        |cols|
            |stmt|
                match gen_first(cols)(stmt) {
                    Ok(first) =>
                        match gen_second(cols)(stmt) {
                            Ok(second) => Ok(mapper(first, second))
                            Err(e) => Err(e)
                        }
                    Err(e) => Err(e)
                }

    ## Transform the output of a decoder by applying a function to the decoded value.
    map_value = |gen_decode, mapper|
        |cols|
            |stmt|
                match gen_decode(cols)(stmt) {
                    Ok(val) => Ok(mapper(val))
                    Err(e) => Err(e)
                }

    ## Transform a decoder's output with a function returning a `Try`.
    map_value_result = |gen_decode, mapper|
        |cols|
            |stmt|
                match gen_decode(cols)(stmt) {
                    Ok(val) => mapper(val)
                    Err(e) => Err(e)
                }

    # internal use only — look the named column's value up in the current row.
    lookup_value! = |cols, stmt, name|
        match cols.find_first_index(|x| x == name) {
            Ok(index) => column_value!(stmt, index)
            Err(NotFound) => Err(NoSuchField(name))
        }

    # ---- Leaf decoders ---------------------------------------------------------

    ## Decode a [Value] keeping it tagged.
    tagged_value = |name|
        |cols|
            |stmt| lookup_value!(cols, stmt, name)

    ## Decode a column to a [Str].
    str = |name|
        |cols|
            |stmt|
                match lookup_value!(cols, stmt, name) {
                    Ok(String(s)) => Ok(s)
                    Ok(other) => to_unexpected_type_err(other)
                    Err(e) => Err(e)
                }

    ## Decode a column to a [List U8].
    bytes = |name|
        |cols|
            |stmt|
                match lookup_value!(cols, stmt, name) {
                    Ok(Bytes(b)) => Ok(b)
                    Ok(other) => to_unexpected_type_err(other)
                    Err(e) => Err(e)
                }

    ## Decode a column to a [I64].
    i64 = |name| int_decoder(name, |n| Ok(n))

    ## Decode a column to a [I32].
    i32 = |name| int_decoder(name, |n| bounds_err(I64.to_i32_try(n)))

    ## Decode a column to a [I16].
    i16 = |name| int_decoder(name, |n| bounds_err(I64.to_i16_try(n)))

    ## Decode a column to a [I8].
    i8 = |name| int_decoder(name, |n| bounds_err(I64.to_i8_try(n)))

    ## Decode a column to a [U64].
    u64 = |name| int_decoder(name, |n| bounds_err(I64.to_u64_try(n)))

    ## Decode a column to a [U32].
    u32 = |name| int_decoder(name, |n| bounds_err(I64.to_u32_try(n)))

    ## Decode a column to a [U16].
    u16 = |name| int_decoder(name, |n| bounds_err(I64.to_u16_try(n)))

    ## Decode a column to a [U8].
    u8 = |name| int_decoder(name, |n| bounds_err(I64.to_u8_try(n)))

    ## Decode a column to a [F64].
    f64 = |name| real_decoder(name, |r| Ok(r))

    # Nullable decoders return `NotNull(value)` for a present value, or `Null` when
    # the column holds SQL NULL. Useful for nullable columns.

    ## Decode a nullable column to `[NotNull(Str), Null]`.
    nullable_str = |name|
        |cols|
            |stmt|
                match lookup_value!(cols, stmt, name) {
                    Ok(String(s)) => Ok(NotNull(s))
                    Ok(Null) => Ok(Null)
                    Ok(other) => to_unexpected_type_err(other)
                    Err(e) => Err(e)
                }

    ## Decode a nullable column to `[NotNull(List(U8)), Null]`.
    nullable_bytes = |name|
        |cols|
            |stmt|
                match lookup_value!(cols, stmt, name) {
                    Ok(Bytes(b)) => Ok(NotNull(b))
                    Ok(Null) => Ok(Null)
                    Ok(other) => to_unexpected_type_err(other)
                    Err(e) => Err(e)
                }

    ## Decode a nullable column to `[NotNull(I64), Null]`.
    nullable_i64 = |name| nullable_int_decoder(name, |n| Ok(n))

    ## Decode a nullable column to `[NotNull(I32), Null]`.
    nullable_i32 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_i32_try(n)))

    ## Decode a nullable column to `[NotNull(I16), Null]`.
    nullable_i16 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_i16_try(n)))

    ## Decode a nullable column to `[NotNull(I8), Null]`.
    nullable_i8 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_i8_try(n)))

    ## Decode a nullable column to `[NotNull(U64), Null]`.
    nullable_u64 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_u64_try(n)))

    ## Decode a nullable column to `[NotNull(U32), Null]`.
    nullable_u32 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_u32_try(n)))

    ## Decode a nullable column to `[NotNull(U16), Null]`.
    nullable_u16 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_u16_try(n)))

    ## Decode a nullable column to `[NotNull(U8), Null]`.
    nullable_u8 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_u8_try(n)))

    ## Decode a nullable column to `[NotNull(F64), Null]`.
    nullable_f64 = |name| nullable_real_decoder(name, |r| Ok(r))

    # internal use only
    nullable_int_decoder = |name, cast|
        |cols|
            |stmt|
                match lookup_value!(cols, stmt, name) {
                    Ok(Integer(n)) =>
                        match cast(n) {
                            Ok(v) => Ok(NotNull(v))
                            Err(e) => Err(e)
                        }
                    Ok(Null) => Ok(Null)
                    Ok(other) => to_unexpected_type_err(other)
                    Err(e) => Err(e)
                }

    # internal use only
    nullable_real_decoder = |name, cast|
        |cols|
            |stmt|
                match lookup_value!(cols, stmt, name) {
                    Ok(Real(r)) =>
                        match cast(r) {
                            Ok(v) => Ok(NotNull(v))
                            Err(e) => Err(e)
                        }
                    Ok(Null) => Ok(Null)
                    Ok(other) => to_unexpected_type_err(other)
                    Err(e) => Err(e)
                }

    # internal use only
    int_decoder = |name, cast|
        |cols|
            |stmt|
                match lookup_value!(cols, stmt, name) {
                    Ok(Integer(n)) => cast(n)
                    Ok(other) => to_unexpected_type_err(other)
                    Err(e) => Err(e)
                }

    # internal use only
    real_decoder = |name, cast|
        |cols|
            |stmt|
                match lookup_value!(cols, stmt, name) {
                    Ok(Real(r)) => cast(r)
                    Ok(other) => to_unexpected_type_err(other)
                    Err(e) => Err(e)
                }

    ## Convert a [ErrCode] to a pretty string for display purposes.
    errcode_to_str = |code|
        match code {
            Error => "Error: Sql error or missing database"
            Internal => "Internal: Internal logic error in Sqlite"
            Perm => "Perm: Access permission denied"
            Abort => "Abort: Callback routine requested an abort"
            Busy => "Busy: The database file is locked"
            Locked => "Locked: A table in the database is locked"
            NoMem => "NoMem: A malloc() failed"
            ReadOnly => "ReadOnly: Attempt to write a readonly database"
            Interrupt => "Interrupt: Operation terminated by sqlite3_interrupt("
            IOErr => "IOErr: Some kind of disk I/O error occurred"
            Corrupt => "Corrupt: The database disk image is malformed"
            NotFound => "NotFound: Unknown opcode in sqlite3_file_control()"
            Full => "Full: Insertion failed because database is full"
            CanNotOpen => "CanNotOpen: Unable to open the database file"
            Protocol => "Protocol: Database lock protocol error"
            Empty => "Empty: Database is empty"
            Schema => "Schema: The database schema changed"
            TooBig => "TooBig: String or BLOB exceeds size limit"
            Constraint => "Constraint: Abort due to constraint violation"
            Mismatch => "Mismatch: Data type mismatch"
            Misuse => "Misuse: Library used incorrectly"
            NoLFS => "NoLFS: Uses OS features not supported on host"
            AuthDenied => "AuthDenied: Authorization denied"
            Format => "Format: Auxiliary database format error"
            OutOfRange => "OutOfRange: 2nd parameter to sqlite3_bind out of range"
            NotADatabase => "NotADatabase: File opened that is not a database file"
            Notice => "Notice: Notifications from sqlite3_log()"
            Warning => "Warning: Warnings from sqlite3_log()"
            Row => "Row: sqlite3_step() has another row ready"
            Done => "Done: sqlite3_step() has finished executing"
            Unknown(c) => "Unknown: error code ${I64.to_str(c)} not known"
        }
}

# ---- internal helpers (module-private) -----------------------------------------

to_unexpected_type_err = |val| {
    type =
        match val {
            Integer(_) => Integer
            Real(_) => Real
            String(_) => String
            Bytes(_) => Bytes
            Null => Null
        }
    Err(UnexpectedType(type))
}

bounds_err = |result|
    match result {
        Ok(v) => Ok(v)
        Err(_) => Err(IntOutOfBounds)
    }

code_from_i64 : I64 -> Sqlite.ErrCode
code_from_i64 = |code|
    match code {
        0 => Error
        1 => Error
        2 => Internal
        3 => Perm
        4 => Abort
        5 => Busy
        6 => Locked
        7 => NoMem
        8 => ReadOnly
        9 => Interrupt
        10 => IOErr
        11 => Corrupt
        12 => NotFound
        13 => Full
        14 => CanNotOpen
        15 => Protocol
        16 => Empty
        17 => Schema
        18 => TooBig
        19 => Constraint
        20 => Mismatch
        21 => Misuse
        22 => NoLFS
        23 => AuthDenied
        24 => Format
        25 => OutOfRange
        26 => NotADatabase
        27 => Notice
        28 => Warning
        100 => Row
        101 => Done
        other => Unknown(other)
    }
