app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.File
import pf.Http
import pf.Sqlite
import pf.Stderr
import pf.Stdout
import http.Response

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            cleanup!() ?? {}
            Stdout.line!("Ran all Sqlite tests.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            cleanup!() ?? {}
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

db_path = "sqlite-test.db"

run_tests! : () => Try({}, _)
run_tests! = || {
    cleanup!()?
    create_schema!()?
    insert_rows!()?

    test_decoders!()?
    test_query_one!()?
    test_prepared_update!()?
    test_binding_validation!()?
    test_tagged_value!()?
    test_execute_rejects_rows!()
}

create_schema! : () => Try({}, _)
create_schema! = ||
    Sqlite.execute!({
        path: db_path,
        query: "CREATE TABLE test (id INTEGER PRIMARY KEY, col_text TEXT NOT NULL, col_bytes BLOB NOT NULL, col_i32 INTEGER NOT NULL, col_i16 INTEGER NOT NULL, col_i8 INTEGER NOT NULL, col_u32 INTEGER NOT NULL, col_u16 INTEGER NOT NULL, col_u8 INTEGER NOT NULL, col_f64 REAL NOT NULL, col_f32 REAL NOT NULL, col_nullable_str TEXT, col_nullable_bytes BLOB, col_nullable_i64 INTEGER, col_nullable_i32 INTEGER, col_nullable_i16 INTEGER, col_nullable_i8 INTEGER, col_nullable_u64 INTEGER, col_nullable_u32 INTEGER, col_nullable_u16 INTEGER, col_nullable_u8 INTEGER, col_nullable_f64 REAL, col_nullable_f32 REAL);",
        bindings: [],
    })

insert_rows! : () => Try({}, _)
insert_rows! = || {
    Sqlite.execute!({
        path: db_path,
        query: "INSERT INTO test (id, col_text, col_bytes, col_i32, col_i16, col_i8, col_u32, col_u16, col_u8, col_f64, col_f32) VALUES (1, 'example text', x'010203', 2147483647, 32767, 127, 4294967295, 65535, 255, 3.5, 4.5);",
        bindings: [],
    })?

    Sqlite.execute!({
        path: db_path,
        query: "INSERT INTO test (id, col_text, col_bytes, col_i32, col_i16, col_i8, col_u32, col_u16, col_u8, col_f64, col_f32, col_nullable_str, col_nullable_bytes, col_nullable_i64, col_nullable_i32, col_nullable_i16, col_nullable_i8, col_nullable_u64, col_nullable_u32, col_nullable_u16, col_nullable_u8, col_nullable_f64, col_nullable_f32) VALUES (2, 'sample text', x'0405', -2147483648, -32768, -128, 42, 43, 44, 5.5, 6.5, 'nullable text', x'0607', -9, -10, -11, -12, 13, 14, 15, 16, 7.5, 8.5);",
        bindings: [],
    })
}

test_decoders! : () => Try({}, _)
test_decoders! = || {
    rows =
        Sqlite.query_many!({
            path: db_path,
            query: "SELECT * FROM test ORDER BY id;",
            bindings: [],
            rows: decode_all_columns,
        })?

    expect_true(rows.len() == 2, "expected two rows")?

    first = List.first(rows)?
    expect_true(first.col_text == "example text", "expected first text column")?
    expect_true(first.col_bytes == [1, 2, 3], "expected first bytes column")?
    expect_true(first.col_i32 == 2_147_483_647, "expected first i32 column")?
    expect_true(first.col_i16 == 32_767, "expected first i16 column")?
    expect_true(first.col_i8 == 127, "expected first i8 column")?
    expect_true(first.col_u32 == 4_294_967_295, "expected first u32 column")?
    expect_true(first.col_u16 == 65_535, "expected first u16 column")?
    expect_true(first.col_u8 == 255, "expected first u8 column")?
    expect_true(first.col_nullable_str == Null, "expected nullable str to be Null")?
    expect_true(first.col_nullable_bytes == Null, "expected nullable bytes to be Null")?

    second = rows.get(1)?
    expect_true(second.col_nullable_str == NotNull("nullable text"), "expected nullable str to decode")?
    expect_true(second.col_nullable_bytes == NotNull([6, 7]), "expected nullable bytes to decode")?
    expect_true(second.col_nullable_i64 == NotNull(-9), "expected nullable i64 to decode")?
    expect_true(second.col_nullable_u8 == NotNull(16), "expected nullable u8 to decode")?

    Ok({})
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
        col_f32 = Sqlite.f32("col_f32")(cols)(stmt)?
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
        col_nullable_f32 = Sqlite.nullable_f32("col_nullable_f32")(cols)(stmt)?

        Ok({
            col_text,
            col_bytes,
            col_i32,
            col_i16,
            col_i8,
            col_u32,
            col_u16,
            col_u8,
            col_f64,
            col_f32,
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
            col_nullable_f32,
        })
    }

test_query_one! : () => Try({}, _)
test_query_one! = || {
    count =
        Sqlite.query!({
            path: db_path,
            query: "SELECT COUNT(*) AS count FROM test;",
            bindings: [],
            row: Sqlite.u64("count"),
        })?

    expect_true(count == 2, "expected row count from query!")?

    prepared_count =
        Sqlite.prepare!({
            path: db_path,
            query: "SELECT COUNT(*) AS count FROM test;",
        })?

    count_prepared =
        Sqlite.query_prepared!({
            stmt: prepared_count,
            bindings: [],
            row: Sqlite.u64("count"),
        })?

    expect_true(count_prepared == 2, "expected row count from query_prepared!")
}

test_prepared_update! : () => Try({}, _)
test_prepared_update! = || {
    prepared_update =
        Sqlite.prepare!({
            path: db_path,
            query: "UPDATE test SET col_text = :col_text WHERE id = :id;",
        })?

    Sqlite.execute_prepared!({
        stmt: prepared_update,
        bindings: [
            { name: ":id", value: Integer(1) },
            { name: ":col_text", value: String("Updated text 1") },
        ],
    })?

    updated_rows =
        Sqlite.query_many!({
            path: db_path,
            query: "SELECT col_text FROM test ORDER BY id;",
            bindings: [],
            rows: Sqlite.str("col_text"),
        })?

    expect_true(List.contains(updated_rows, "Updated text 1"), "expected prepared update to change row text")
}

test_binding_validation! : () => Try({}, _)
test_binding_validation! = || {
    update_query = "UPDATE test SET col_text = :col_text WHERE id = :id;"

    match Sqlite.execute!({
        path: db_path,
        query: update_query,
        bindings: [{ name: ":id", value: Integer(1) }],
    }) {
        Err(SqliteErr(Error, _)) => Ok({})
        other => Err(FailedExpectation("expected missing binding to fail, got ${Str.inspect(other)}"))
    }?

    match Sqlite.execute!({
        path: db_path,
        query: update_query,
        bindings: [
            { name: ":id", value: Integer(1) },
            { name: ":col_text", value: String("unused") },
            { name: ":extra", value: String("unused") },
        ],
    }) {
        Err(SqliteErr(Error, _)) => Ok({})
        other => Err(FailedExpectation("expected unknown binding to fail, got ${Str.inspect(other)}"))
    }?

    match Sqlite.execute!({
        path: db_path,
        query: update_query,
        bindings: [
            { name: ":id", value: Integer(1) },
            { name: ":id", value: Integer(1) },
            { name: ":col_text", value: String("unused") },
        ],
    }) {
        Err(SqliteErr(Error, _)) => Ok({})
        other => Err(FailedExpectation("expected duplicate binding to fail, got ${Str.inspect(other)}"))
    }?

    match Sqlite.execute!({
        path: db_path,
        query: "UPDATE test SET col_text = ? WHERE id = :id;",
        bindings: [{ name: ":id", value: Integer(1) }],
    }) {
        Err(SqliteErr(Error, _)) => Ok({})
        other => Err(FailedExpectation("expected positional parameter to fail, got ${Str.inspect(other)}"))
    }?

    match Sqlite.execute!({
        path: db_path,
        query: "",
        bindings: [],
    }) {
        Err(SqliteErr(Error, _)) => Ok({})
        other => Err(FailedExpectation("expected empty SQL to fail, got ${Str.inspect(other)}"))
    }?

    match Sqlite.execute!({
        path: db_path,
        query: "SELECT id FROM test; SELECT id FROM test;",
        bindings: [],
    }) {
        Err(SqliteErr(Error, _)) => Ok({})
        other => Err(FailedExpectation("expected multiple SQL statements to fail, got ${Str.inspect(other)}"))
    }
}

test_tagged_value! : () => Try({}, _)
test_tagged_value! = || {
    values =
        Sqlite.query_many!({
            path: db_path,
            query: "SELECT col_text FROM test ORDER BY id;",
            bindings: [],
            rows: Sqlite.tagged_value("col_text"),
        })?

    match List.first(values) {
        Ok(String(_)) => Ok({})
        other => Err(FailedExpectation("expected tagged value to decode as String, got ${Str.inspect(other)}"))
    }
}

test_execute_rejects_rows! : () => Try({}, _)
test_execute_rejects_rows! = ||
    match Sqlite.execute!({ path: db_path, query: "SELECT * FROM test;", bindings: [] }) {
        Err(RowsReturnedUseQueryInstead) => Ok({})
        other => Err(FailedExpectation("expected execute! to reject row-returning SQL, got ${Str.inspect(other)}"))
    }

expect_true = |condition, message|
    if condition {
        Ok({})
    } else {
        Err(FailedExpectation(message))
    }

cleanup! : () => Try({}, _)
cleanup! = || {
    File.delete!(db_path) ?? {}
    Ok({})
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_, _|
    Ok(Response.from_status(200).with_body(Str.to_utf8("I am a test.")))
