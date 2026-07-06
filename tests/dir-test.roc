app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Dir
import pf.File
import pf.Http
import pf.Path
import pf.Stderr
import pf.Stdout
import http.Response

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            cleanup_test_dirs!() ?? {}
            Stdout.line!("Ran all Dir tests.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            cleanup_test_dirs!() ?? {}
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    cleanup_test_dirs!()?

    test_dir_create!()?
    test_dir_create_all!()?
    test_dir_delete_empty!()?
    test_dir_delete_all!()?

    Ok({})
}

test_dir_create! : () => Try({}, _)
test_dir_create! = || {
    test_dir = "test_dir_create"
    Dir.create!(test_dir)?
    expect_is_dir!(test_dir)?

    expect_err(Dir.create!(test_dir), "Dir.create! should fail for an existing directory")?
    expect_err(Dir.create!("non_existent_parent/test_dir"), "Dir.create! should fail when the parent is missing")?

    Ok({})
}

test_dir_create_all! : () => Try({}, _)
test_dir_create_all! = || {
    nested = "test_parent_all/test_child_all/test_grandchild_all"
    Dir.create_all!(nested)?
    expect_is_dir!(nested)?

    Dir.create_all!(nested)?

    single = "test_single_with_create_all"
    Dir.create_all!(single)?
    expect_is_dir!(single)?

    Ok({})
}

test_dir_delete_empty! : () => Try({}, _)
test_dir_delete_empty! = || {
    empty_dir = "test_empty_for_delete"
    Dir.create!(empty_dir)?
    expect_is_dir!(empty_dir)?

    Dir.delete_empty!(empty_dir)?
    expect_not_dir!(empty_dir)?

    non_empty_dir = "test_non_empty_for_delete"
    Dir.create!(non_empty_dir)?
    File.write_utf8!("${non_empty_dir}/test_file.txt", "test content")?
    expect_err(Dir.delete_empty!(non_empty_dir), "Dir.delete_empty! should fail for a non-empty directory")?
    expect_is_dir!(non_empty_dir)?

    expect_err(Dir.delete_empty!("non_existent_directory"), "Dir.delete_empty! should fail for a missing directory")?

    Ok({})
}

test_dir_delete_all! : () => Try({}, _)
test_dir_delete_all! = || {
    complex_dir = "test_complex_for_delete_all"
    Dir.create_all!("${complex_dir}/subdir1/subsubdir")?
    Dir.create_all!("${complex_dir}/subdir2")?

    File.write_utf8!("${complex_dir}/file1.txt", "file1 content")?
    File.write_utf8!("${complex_dir}/subdir1/file2.txt", "file2 content")?
    File.write_utf8!("${complex_dir}/subdir1/subsubdir/file3.txt", "file3 content")?
    File.write_utf8!("${complex_dir}/subdir2/file4.txt", "file4 content")?

    expect_is_dir!(complex_dir)?
    Dir.delete_all!(complex_dir)?
    expect_not_dir!(complex_dir)?

    expect_err(Dir.delete_all!("non_existent_directory_for_delete_all"), "Dir.delete_all! should fail for a missing directory")?

    Ok({})
}

expect_is_dir! : Str => Try({}, _)
expect_is_dir! = |path| {
    is_dir = Path.is_dir!(Path.from_str(path))?
    expect_true(is_dir, "Expected ${path} to be a directory")
}

expect_not_dir! : Str => Try({}, _)
expect_not_dir! = |path|
    match Path.is_dir!(Path.from_str(path)) {
        Ok(Bool.False) => Ok({})
        Err(_) => Ok({})
        Ok(Bool.True) => Err(FailedExpectation("Expected ${path} not to be a directory"))
    }

expect_err = |result, message|
    match result {
        Ok(_) => Err(FailedExpectation(message))
        Err(_) => Ok({})
    }

expect_true = |condition, message|
    if condition {
        Ok({})
    } else {
        Err(FailedExpectation(message))
    }

cleanup_test_dirs! : () => Try({}, _)
cleanup_test_dirs! = || {
    for dir in [
        "test_dir_create",
        "test_parent_all",
        "test_single_with_create_all",
        "test_empty_for_delete",
        "test_non_empty_for_delete",
        "test_complex_for_delete_all",
    ] {
        Dir.delete_all!(dir) ?? {}
    }

    Ok({})
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_, _|
    Ok(Response.from_status(200).with_body(Str.to_utf8("I am a test.")))
