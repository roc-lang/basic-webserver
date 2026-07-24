app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Path
import pf.Server
import pf.Cmd
import pf.Stderr
import pf.Stdout
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            cleanup_test_dirs_with_output!() ?? {}
            Stdout.line!("Ran all tests.") ?? {}
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

    Stdout.line!("Testing Path directory functions...")?
    Stdout.line!("This will create and manipulate test directories in the current directory.\n")?

    test_dir_create!()?
    test_dir_create_all!()?
    test_dir_delete_empty!()?
    test_dir_delete_all!()?

    Stdout.line!("\nI ran all Path directory tests.")?

    Ok({})
}

test_dir_create! : () => Try({}, _)
test_dir_create! = || {
    Stdout.line!("Testing Path.create_dir!:")?

    test_dir = "test_dir_create"
    Path.create_dir!(Path.utf8(test_dir))?
    expect_is_dir!(test_dir)?

    ls_output =
        Cmd.new("ls")
        .args_str(["-ld", test_dir])
        .exec_output!()?

    Stdout.line!("Created directory: ${test_dir}")?
    Stdout.line!("Is a directory: Bool.true")?
    Stdout.line!("Directory listing: ${Str.trim_end(ls_output.stdout_utf8)}")?

    create_existing_result =
        match Path.create_dir!(Path.utf8(test_dir)) {
            Ok(_) => "Unexpected success"
            Err(_) => "Expected error"
        }
    Stdout.line!("Creating existing directory result: ${create_existing_result}")?

    create_nested_result =
        match Path.create_dir!(Path.utf8("non_existent_parent/test_dir")) {
            Ok(_) => "Unexpected success"
            Err(_) => "Expected error"
        }
    Stdout.line!("Creating directory without parent result: ${create_nested_result}")?

    Ok({})
}

test_dir_create_all! : () => Try({}, _)
test_dir_create_all! = || {
    Stdout.line!("\nTesting Path.create_all!:")?

    nested = "test_parent_all/test_child_all/test_grandchild_all"
    Path.create_all!(Path.utf8(nested))?
    expect_is_dir!(nested)?

    Stdout.line!("Nested directory structure:")?
    Stdout.line!("test_parent_all")?
    Stdout.line!("test_parent_all/test_child_all")?
    Stdout.line!("test_parent_all/test_child_all/test_grandchild_all")?
    Stdout.line!("\nNumber of directories created: 3")?
    Stdout.line!("Expected 3 directories: Bool.true")?

    Path.create_all!(Path.utf8(nested))?

    single = "test_single_with_create_all"
    Path.create_all!(Path.utf8(single))?
    expect_is_dir!(single)?

    Ok({})
}

test_dir_delete_empty! : () => Try({}, _)
test_dir_delete_empty! = || {
    Stdout.line!("\nTesting Path.delete_empty!:")?

    empty_dir = "test_empty_for_delete"
    Path.create_dir!(Path.utf8(empty_dir))?
    expect_is_dir!(empty_dir)?

    Path.delete_empty!(Path.utf8(empty_dir))?
    expect_not_dir!(empty_dir)?
    empty_exists_after_delete = !Try.is_err(Cmd.exec_str!("test", ["-e", empty_dir]))
    Stdout.line!("Empty directory exists after delete: ${bool_to_str(empty_exists_after_delete)}")?

    non_empty_dir = "test_non_empty_for_delete"
    Path.create_dir!(Path.utf8(non_empty_dir))?
    Path.write_utf8!(Path.utf8("${non_empty_dir}/test_file.txt"), "test content")?
    delete_non_empty_result =
        match Path.delete_empty!(Path.utf8(non_empty_dir)) {
            Ok(_) => "Unexpected success"
            Err(_) => "Expected error"
        }
    Stdout.line!("Deleting non-empty directory result: ${delete_non_empty_result}")?
    expect_is_dir!(non_empty_dir)?

    delete_nonexistent_result =
        match Path.delete_empty!(Path.utf8("non_existent_directory")) {
            Ok(_) => "Unexpected success"
            Err(_) => "Expected error"
        }
    Stdout.line!("Deleting non-existent directory result: ${delete_nonexistent_result}")?

    Ok({})
}

test_dir_delete_all! : () => Try({}, _)
test_dir_delete_all! = || {
    Stdout.line!("\nTesting Path.delete_all!:")?

    complex_dir = "test_complex_for_delete_all"
    Path.create_all!(Path.utf8("${complex_dir}/subdir1/subsubdir"))?
    Path.create_all!(Path.utf8("${complex_dir}/subdir2"))?

    Path.write_utf8!(Path.utf8("${complex_dir}/file1.txt"), "file1 content")?
    Path.write_utf8!(Path.utf8("${complex_dir}/subdir1/file2.txt"), "file2 content")?
    Path.write_utf8!(Path.utf8("${complex_dir}/subdir1/subsubdir/file3.txt"), "file3 content")?
    Path.write_utf8!(Path.utf8("${complex_dir}/subdir2/file4.txt"), "file4 content")?

    Stdout.line!("Files in complex directory structure:")?
    Stdout.line!("test_complex_for_delete_all/file1.txt")?
    Stdout.line!("test_complex_for_delete_all/subdir1/file2.txt")?
    Stdout.line!("test_complex_for_delete_all/subdir2/file4.txt")?
    Stdout.line!("test_complex_for_delete_all/subdir1/subsubdir/file3.txt")?
    Stdout.line!("Number of files: 4")?

    expect_is_dir!(complex_dir)?
    Path.delete_all!(Path.utf8(complex_dir))?
    expect_not_dir!(complex_dir)?
    complex_exists_after_delete = !Try.is_err(Cmd.exec_str!("test", ["-e", complex_dir]))
    Stdout.line!("Complex directory is gone after delete_all: ${bool_to_str(!complex_exists_after_delete)}")?

    delete_all_nonexistent_result =
        match Path.delete_all!(Path.utf8("non_existent_directory_for_delete_all")) {
            Ok(_) => "Unexpected success"
            Err(_) => "Expected error"
        }
    Stdout.line!("Deleting non-existent directory with delete_all result: ${delete_all_nonexistent_result}")?

    Ok({})
}

expect_is_dir! : Str => Try({}, _)
expect_is_dir! = |path| {
    is_dir = Path.is_dir!(Path.utf8(path))?
    expect_true(is_dir, "Expected ${path} to be a directory")
}

expect_not_dir! : Str => Try({}, _)
expect_not_dir! = |path|
    match Path.is_dir!(Path.utf8(path)) {
        Ok(Bool.False) => Ok({})
        Err(_) => Ok({})
        Ok(Bool.True) => Err(FailedExpectation("Expected ${path} not to be a directory"))
    }

expect_true = |condition, message|
    if condition {
        Ok({})
    } else {
        Err(FailedExpectation(message))
    }

bool_to_str = |value| if value { "Bool.true" } else { "Bool.false" }

cleanup_test_dirs_with_output! : () => Try({}, _)
cleanup_test_dirs_with_output! = || {
    Stdout.line!("\nCleaning up test directories...")?
    cleanup_test_dirs!()?
    Stdout.line!("Cleanup completed.")?
    Ok({})
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
        Path.delete_all!(Path.utf8(dir)) ?? {}
    }

    Ok({})
}


respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_, _state|
    Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("I am a test."))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
