app [Model, init!, respond!] { 
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Sqlite
import pf.Env

Model : {}

init! : {} => Result Model _
init! = |{}|
    when run_tests!({}) is
        Ok(_) ->
            Err(Exit(0, "Ran all tests."))
        Err(err) ->
            Err(Exit(1, "Test run failed:\n\t${Inspect.to_str(err)}"))

run_tests! : {} => Result {} _
run_tests! = |{}|
    db_path = Env.var!("DB_PATH")?

    # Test Sqlite.str, Sqlite.bytes, Sqlite.i32...

    all_rows = Sqlite.query_many!({
        path: db_path,
        query: "SELECT * FROM test;",
        bindings: [],
        # This uses the record builder syntax: https://www.roc-lang.org/examples/RecordBuilder/README.html
        rows: { Sqlite.decode_record <-
            col_text: Sqlite.str("col_text"),
            col_bytes: Sqlite.bytes("col_bytes"),
            col_i32: Sqlite.i32("col_i32"),
            col_i16: Sqlite.i16("col_i16"),
            col_i8: Sqlite.i8("col_i8"),
            col_u32: Sqlite.u32("col_u32"),
            col_u16: Sqlite.u16("col_u16"),
            col_u8: Sqlite.u8("col_u8"),
            col_f64: Sqlite.f64("col_f64"),
            col_f32: Sqlite.f32("col_f32"),
            col_nullable_str: Sqlite.nullable_str("col_nullable_str"),
            col_nullable_bytes: Sqlite.nullable_bytes("col_nullable_bytes"),
            col_nullable_i64: Sqlite.nullable_i64("col_nullable_i64"),
            col_nullable_i32: Sqlite.nullable_i32("col_nullable_i32"),
            col_nullable_i16: Sqlite.nullable_i16("col_nullable_i16"),
            col_nullable_i8: Sqlite.nullable_i8("col_nullable_i8"),
            col_nullable_u64: Sqlite.nullable_u64("col_nullable_u64"),
            col_nullable_u32: Sqlite.nullable_u32("col_nullable_u32"),
            col_nullable_u16: Sqlite.nullable_u16("col_nullable_u16"),
            col_nullable_u8: Sqlite.nullable_u8("col_nullable_u8"),
            col_nullable_f64: Sqlite.nullable_f64("col_nullable_f64"),
            col_nullable_f32: Sqlite.nullable_f32("col_nullable_f32"),
        },
    }) ? |err| QuerManyFailed(err)

    rows_texts_str =
        all_rows
        |> List.map(|row| Inspect.to_str(row))
        |> Str.join_with("\n")

    Stdout.line!("Rows: ${rows_texts_str}")?

    # Test query_prepared! with count

    prepared_count = Sqlite.prepare!({
        path: db_path,
        query: "SELECT COUNT(*) as \"count\" FROM test;",
    }) ? |err| PrepareFailed(err)

    count = Sqlite.query_prepared!({
        stmt: prepared_count,
        bindings: [],
        row: Sqlite.u64("count"),
    }) ? |err| QueryPreparedFailed(err)


    Stdout.line!("Row count: ${Num.to_str(count)}")?

    # Test execute_prepared! with different params

    prepared_update = Sqlite.prepare!({
        path: db_path,
        query: "UPDATE test SET col_text = :col_text WHERE id = :id;",
    }) ? |err| PreparedUpdateFailed(err)

    Sqlite.execute_prepared!({
        stmt: prepared_update,
        bindings: [
            { name: ":id", value: Integer(1) },
            { name: ":col_text", value: String("Updated text 1") },
        ],
    }) ? |err| ExecutePreparedFailed(err)

    Sqlite.execute_prepared!({
        stmt: prepared_update,
        bindings: [
            { name: ":id", value: Integer(2) },
            { name: ":col_text", value: String("Updated text 2") },
        ],
    }) ? |err| ExecutePrepared2Failed(err)

    # Check if the updates were successful
    updated_rows = Sqlite.query_many!({
        path: db_path,
        query: "SELECT COL_TEXT FROM test;",
        bindings: [],
        rows: Sqlite.str("col_text"),
    }) ? |err| QueryUpdatedRowsFailed(err)

    Stdout.line!("Updated rows: ${Inspect.to_str(updated_rows)}")?

    # revert update
    Sqlite.execute_prepared!({
        stmt: prepared_update,
        bindings: [
            { name: ":id", value: Integer(1) },
            { name: ":col_text", value: String("example text") },
        ],
    }) ? |err| ExecutePrepared3Failed(err)

    Sqlite.execute_prepared!({
        stmt: prepared_update,
        bindings: [
            { name: ":id", value: Integer(2) },
            { name: ":col_text", value: String("sample text") },
        ],
    }) ? |err| ExecutePrepared4Failed(err)

    # Test tagged_value
    tagged_value_test = Sqlite.query_many!({
        path: db_path,
        query: "SELECT * FROM test;",
        bindings: [],
        # This uses the record builder syntax: https://www.roc-lang.org/examples/RecordBuilder/README.html
        rows: Sqlite.tagged_value("col_text"),
    }) ? |err| QueryMany2Failed(err)

    Stdout.line!("Tagged value test: ${Inspect.to_str(tagged_value_test)}")?

    # Let's try to trigger a `Data type mismatch` error
    sql_res = Sqlite.execute!({
        path: db_path,
        query: "UPDATE test SET id = :id WHERE col_text = :col_text;",
        bindings: [
            { name: ":col_text", value: String("sample text") },
            { name: ":id", value: String("This should be an integer") },
        ],
    })

    when sql_res is
        Ok(_) ->
            crash "This should be an error."
        Err(err) ->
            when err is
                SqliteErr(err_type, _) ->
                    Stdout.line!("Error: ${Sqlite.errcode_to_str(err_type)}")?
                other_err ->
                    crash "This should be an SqliteErr, but it was:\n\t${Inspect.to_str(other_err)}"

    Ok({})

respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |_, _|

    Ok(
        {
            status: 200,
            headers: [],
            body: Str.to_utf8("I am a test."),
        },
    )
