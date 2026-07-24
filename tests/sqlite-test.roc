app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Env
import pf.Server
import pf.Sqlite
import pf.Path
import pf.Stderr
import pf.Stdout
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            Stdout.line!("Ran all tests.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    db_path = Path.from_os_str(Env.var!("DB_PATH") ? |_| EnvVarNotFound("DB_PATH"))

    rows = test_decoders!(db_path)?
    rows_texts = Str.join_with(rows.map(Str.inspect), "\n")
    Stdout.line!("Rows: ${rows_texts}")?

    test_query_one!(db_path)?
    test_prepared_update!(db_path)?
    test_tagged_value!(db_path)?
    test_data_type_mismatch!(db_path)
}

DecodedRow := {
    col_text : Str,
    col_bytes : List(U8),
    col_i32 : I32,
    col_i16 : I16,
    col_i8 : I8,
    col_u32 : U32,
    col_u16 : U16,
    col_u8 : U8,
    col_f64 : F64,
    col_nullable_str : [NotNull(Str), Null],
    col_nullable_bytes : [NotNull(List(U8)), Null],
    col_nullable_i64 : [NotNull(I64), Null],
    col_nullable_i32 : [NotNull(I32), Null],
    col_nullable_i16 : [NotNull(I16), Null],
    col_nullable_i8 : [NotNull(I8), Null],
    col_nullable_u64 : [NotNull(U64), Null],
    col_nullable_u32 : [NotNull(U32), Null],
    col_nullable_u16 : [NotNull(U16), Null],
    col_nullable_u8 : [NotNull(U8), Null],
    col_nullable_f64 : [NotNull(F64), Null],
}.{
    to_inspect : DecodedRow -> Str
    to_inspect = |row|
        "{col_bytes: ${Str.inspect(row.col_bytes)}, col_f64: ${Str.inspect(row.col_f64)}, col_i16: ${Str.inspect(row.col_i16)}, col_i32: ${Str.inspect(row.col_i32)}, col_i8: ${Str.inspect(row.col_i8)}, col_nullable_bytes: ${inspect_nullable(row.col_nullable_bytes)}, col_nullable_f64: ${inspect_nullable(row.col_nullable_f64)}, col_nullable_i16: ${inspect_nullable(row.col_nullable_i16)}, col_nullable_i32: ${inspect_nullable(row.col_nullable_i32)}, col_nullable_i64: ${inspect_nullable(row.col_nullable_i64)}, col_nullable_i8: ${inspect_nullable(row.col_nullable_i8)}, col_nullable_str: ${inspect_nullable(row.col_nullable_str)}, col_nullable_u16: ${inspect_nullable(row.col_nullable_u16)}, col_nullable_u32: ${inspect_nullable(row.col_nullable_u32)}, col_nullable_u64: ${inspect_nullable(row.col_nullable_u64)}, col_nullable_u8: ${inspect_nullable(row.col_nullable_u8)}, col_text: ${Str.inspect(row.col_text)}, col_u16: ${Str.inspect(row.col_u16)}, col_u32: ${Str.inspect(row.col_u32)}, col_u8: ${Str.inspect(row.col_u8)}}"
}

TaggedValue := { value : [Null, Real(F64), Integer(I64), String(Str), Bytes(List(U8))] }.{
    to_inspect : TaggedValue -> Str
    to_inspect = |tagged|
        match tagged.value {
            String(str) => "(String ${Str.inspect(str)})"
            Integer(n) => "(Integer ${Str.inspect(n)})"
            Real(n) => "(Real ${Str.inspect(n)})"
            Bytes(bytes) => "(Bytes ${Str.inspect(bytes)})"
            Null => "Null"
        }
}

test_decoders! : Path.Path => Try(List(DecodedRow), _)
test_decoders! = |db_path| {
    rows =
        Sqlite.query_many!({
            path: db_path,
            query: "SELECT * FROM test;",
            bindings: [],
            rows: decode_all_columns,
        })?

    expect_true(rows.len() == 2, "expected two rows")?
    Ok(rows)
}

decode_all_columns = |cols|
    |stmt| {
        col_text = Sqlite.str("col_text")(cols)(stmt)?
        col_bytes = Sqlite.bytes("col_bytes")(cols)(stmt)?
        col_i32 = Sqlite.i32("col_i32")(cols)(stmt)?
        col_i16 = Sqlite.i16("col_i16")(cols)(stmt)?
        col_i8 = Sqlite.i8("col_i8")(cols)(stmt)?
        col_u32 = Sqlite.u32("col_u32")(cols)(stmt)?
        col_u16 = Sqlite.u16("col_u16")(cols)(stmt)?
        col_u8 = Sqlite.u8("col_u8")(cols)(stmt)?
        col_f64 = Sqlite.f64("col_f64")(cols)(stmt)?
        col_nullable_str = Sqlite.nullable_str("col_nullable_str")(cols)(stmt)?
        col_nullable_bytes = Sqlite.nullable_bytes("col_nullable_bytes")(cols)(stmt)?
        col_nullable_i64 = Sqlite.nullable_i64("col_nullable_i64")(cols)(stmt)?
        col_nullable_i32 = Sqlite.nullable_i32("col_nullable_i32")(cols)(stmt)?
        col_nullable_i16 = Sqlite.nullable_i16("col_nullable_i16")(cols)(stmt)?
        col_nullable_i8 = Sqlite.nullable_i8("col_nullable_i8")(cols)(stmt)?
        col_nullable_u64 = Sqlite.nullable_u64("col_nullable_u64")(cols)(stmt)?
        col_nullable_u32 = Sqlite.nullable_u32("col_nullable_u32")(cols)(stmt)?
        col_nullable_u16 = Sqlite.nullable_u16("col_nullable_u16")(cols)(stmt)?
        col_nullable_u8 = Sqlite.nullable_u8("col_nullable_u8")(cols)(stmt)?
        col_nullable_f64 = Sqlite.nullable_f64("col_nullable_f64")(cols)(stmt)?

        Ok(DecodedRow.{
            col_text,
            col_bytes,
            col_i32,
            col_i16,
            col_i8,
            col_u32,
            col_u16,
            col_u8,
            col_f64,
            col_nullable_str,
            col_nullable_bytes,
            col_nullable_i64,
            col_nullable_i32,
            col_nullable_i16,
            col_nullable_i8,
            col_nullable_u64,
            col_nullable_u32,
            col_nullable_u16,
            col_nullable_u8,
            col_nullable_f64,
        })
    }

test_query_one! : Path.Path => Try({}, _)
test_query_one! = |db_path| {
    count =
        Sqlite.query!({
            path: db_path,
            query: "SELECT COUNT(*) as \"count\" FROM test;",
            bindings: [],
            row: Sqlite.u64("count"),
        })?

    expect_true(count == 2, "expected row count from query!")?
    Stdout.line!("Row count: ${count.to_str()}")?

    prepared_count =
        Sqlite.prepare!({
            path: db_path,
            query: "SELECT COUNT(*) as \"count\" FROM test;",
        })?

    count_prepared = prepared_count.query!([], Sqlite.u64("count"))?

    expect_true(count_prepared == 2, "expected row count from query_prepared!")?
    Stdout.line!("Row count (prepared): ${count_prepared.to_str()}")
}

test_prepared_update! : Path.Path => Try({}, _)
test_prepared_update! = |db_path| {
    prepared_update =
        Sqlite.prepare!({
            path: db_path,
            query: "UPDATE test SET col_text = :col_text WHERE id = :id;",
        })?

    prepared_update.execute!([
            { name: ":id", value: Integer(1) },
            { name: ":col_text", value: String("Updated text 1") },
        ])?

    prepared_update.execute!([
            { name: ":id", value: Integer(2) },
            { name: ":col_text", value: String("Updated text 2") },
        ])?

    updated_rows =
        Sqlite.query_many!({
            path: db_path,
            query: "SELECT COL_TEXT FROM test;",
            bindings: [],
            rows: Sqlite.str("col_text"),
        })?

    Stdout.line!("Updated rows: ${Str.inspect(updated_rows)}")?

    prepared_update.execute!([
            { name: ":id", value: Integer(1) },
            { name: ":col_text", value: String("example text") },
        ])?

    prepared_update.execute!([
            { name: ":id", value: Integer(2) },
            { name: ":col_text", value: String("sample text") },
        ])
}

test_tagged_value! : Path.Path => Try({}, _)
test_tagged_value! = |db_path| {
    values =
        Sqlite.query_many!({
            path: db_path,
            query: "SELECT * FROM test;",
            bindings: [],
            rows: |cols| |stmt| {
                value = Sqlite.tagged_value("col_text")(cols)(stmt)?
                Ok(TaggedValue.{ value })
            },
        })?

    Stdout.line!("Tagged value test: ${Str.inspect(values)}")
}

test_data_type_mismatch! : Path.Path => Try({}, _)
test_data_type_mismatch! = |db_path| {
    sql_res =
        Sqlite.execute!({
            path: db_path,
            query: "UPDATE test SET id = :id WHERE col_text = :col_text;",
            bindings: [
                { name: ":col_text", value: String("sample text") },
                { name: ":id", value: String("This should be an integer") },
            ],
        })

    match sql_res {
        Ok(_) => Err(FailedExpectation("expected data type mismatch"))
        Err(SqliteErr(err_type, _)) => Stdout.line!("Error: ${Sqlite.errcode_to_str(err_type)}")
        Err(err) => Err(FailedExpectation("expected SqliteErr, got ${Str.inspect(err)}"))
    }
}

expect_true = |condition, message|
    if condition {
        Ok({})
    } else {
        Err(FailedExpectation(message))
    }

inspect_nullable = |value|
    match value {
        NotNull(inner) => "(NotNull ${Str.inspect(inner)})"
        Null => "Null"
    }


respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_, _state|
    Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("I am a test."))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
