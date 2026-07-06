app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Stderr
import pf.File
import pf.Cmd
import pf.Http
import http.Response

# NOTE: The migrated File module is a reduced subset. This test covers the
# functions that are currently available: read_bytes!, write_bytes!,
# read_utf8!, write_utf8!, delete!, size_in_bytes!, is_executable!,
# is_readable!, is_writable!. (is_file!, is_dir!, type!, hard_link!, rename!,
# exists!, and the buffered reader are not yet migrated.)

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            cleanup_test_files!() ?? {}
            Stdout.line!("Ran all tests.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            cleanup_test_files!() ?? {}
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    Stdout.line!("Testing some File functions...")?
    Stdout.line!("This will create and manipulate test files in the current directory.\n")?

    test_basic_file_operations!()?
    test_file_permissions!()?
    test_file_size!()?
    test_file_delete!()?

    Stdout.line!("\nI ran all file function tests.")
}

test_basic_file_operations! : () => Try({}, _)
test_basic_file_operations! = || {
    Stdout.line!("Testing File.write_bytes! and File.read_bytes!:")?

    test_bytes = [72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33] # "Hello, World!" in bytes
    File.write_bytes!("test_bytes.txt", test_bytes)?

    file_content_bytes = File.read_bytes!("test_bytes.txt")?
    Stdout.line!("Bytes in test_bytes.txt: ${Str.inspect(file_content_bytes)}")?
    Stdout.line!("Bytes match: ${Str.inspect(file_content_bytes == test_bytes)}")?

    Stdout.line!("\nTesting File.write_utf8! and File.read_utf8!:")?

    File.write_utf8!("test_write.txt", "some text content")?
    utf8_file_content = File.read_utf8!("test_write.txt")?
    Stdout.line!("Content of test_write.txt: ${utf8_file_content}")?

    Ok({})
}

test_file_permissions! : () => Try({}, _)
test_file_permissions! = || {
    Stdout.line!("\nTesting File.is_executable!, File.is_readable!, File.is_writable!:")?

    is_executable = File.is_executable!("test_bytes.txt")?
    is_readable = File.is_readable!("test_bytes.txt")?
    is_writable = File.is_writable!("test_bytes.txt")?

    Stdout.line!("Executable: ${Str.inspect(is_executable)}\nReadable: ${Str.inspect(is_readable)}\nWritable: ${Str.inspect(is_writable)}")?

    Ok({})
}

test_file_size! : () => Try({}, _)
test_file_size! = || {
    Stdout.line!("\nTesting File.size_in_bytes!:")?

    file_size = File.size_in_bytes!("test_bytes.txt")?
    Stdout.line!("File.size_in_bytes! returned ${file_size.to_str()} bytes for test_bytes.txt")?

    Ok({})
}

test_file_delete! : () => Try({}, _)
test_file_delete! = || {
    Stdout.line!("\nTesting File.delete!:")?

    File.write_utf8!("test_to_delete.txt", "")?

    # Verify it exists before delete
    Cmd.exec!("test", ["-e", "test_to_delete.txt"])?

    File.delete!("test_to_delete.txt")?

    # Verify it's gone after delete
    exists_res = Cmd.exec!("test", ["-e", "test_to_delete.txt"])
    Stdout.line!("File no longer exists after delete: ${Str.inspect(Try.is_err(exists_res))}")?

    Ok({})
}

cleanup_test_files! : () => Try({}, _)
cleanup_test_files! = || {
    Stdout.line!("\nCleaning up test files...")?

    test_files = [
        "test_bytes.txt",
        "test_write.txt",
        "test_to_delete.txt",
    ]

    for filename in test_files {
        File.delete!(filename) ?? {}
    }

    Stdout.line!("Deleted all files.")
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok(Response.from_status(200).with_body(Str.to_utf8("I am a test.")))
