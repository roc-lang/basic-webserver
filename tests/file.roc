app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Stderr
import pf.File
import pf.Path
import pf.Cmd
import pf.Http
import http.Response

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
    Stdout.line!("Testing filesystem functions...")?
    Stdout.line!("This will create and manipulate test files in the current directory.\n")?

    test_basic_file_operations!()?
    test_file_type_checking!()?
    test_file_reader_with_capacity!()?
    test_hard_link!()?
    test_file_rename!()?
    test_file_exists!()?
    test_file_size!()?
    test_is_dir!()?

    Stdout.line!("\nI ran all filesystem tests.")
}

test_basic_file_operations! : () => Try({}, _)
test_basic_file_operations! = || {
    Stdout.line!("Testing Path.write_bytes! and Path.read_bytes!:")?

    test_bytes = [72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33] # "Hello, World!" in bytes
    Path.write_bytes!(Path.utf8("test_bytes.txt"), test_bytes)?

    file_content_bytes = Path.read_bytes!(Path.utf8("test_bytes.txt"))?
    Stdout.line!("Bytes in test_bytes.txt: ${Str.inspect(file_content_bytes)}")?

    Stdout.line!("\nTesting Path.write_utf8!:")?

    Path.write_utf8!(Path.utf8("test_write.json"), "{\"some\":\"json stuff\"}")?
    json_file_content = Path.read_utf8!(Path.utf8("test_write.json"))?
    Stdout.line!("Content of test_write.json: ${json_file_content}")?

    Ok({})
}

test_file_type_checking! : () => Try({}, _)
test_file_type_checking! = || {
    Stdout.line!("\nTesting Path.is_file!:")?

    if Path.is_file!(Path.utf8("test_bytes.txt"))? {
        Stdout.line!("✓ test_bytes.txt is confirmed to be a file")?
    } else {
        Stderr.line!("✗ test_bytes.txt is not recognized as a file")?
    }

    Stdout.line!("\nTesting Path.is_sym_link!:")?

    if Path.is_sym_link!(Path.utf8("test_bytes.txt"))? {
        Stderr.line!("✗ test_bytes.txt is a symbolic link")?
    } else {
        Stdout.line!("✓ test_bytes.txt is not a symbolic link")?
    }

    Cmd.exec!("ln", ["-s", "test_bytes.txt", "test_symlink.txt"])?

    if Path.is_sym_link!(Path.utf8("test_symlink.txt"))? {
        Stdout.line!("✓ test_symlink.txt is a symbolic link")?
    } else {
        Stderr.line!("✗ test_symlink.txt is not a symbolic link")?
    }

    Stdout.line!("\nTesting Path.type!:")?

    file_type_file = Path.type!(Path.utf8("test_bytes.txt"))?
    Stdout.line!("test_bytes.txt file type: ${Str.inspect(file_type_file)}")?

    file_type_dir = Path.type!(Path.utf8("."))?
    Stdout.line!(". file type: ${Str.inspect(file_type_dir)}")?

    file_type_symlink = Path.type!(Path.utf8("test_symlink.txt"))?
    Stdout.line!("test_symlink.txt file type: ${Str.inspect(file_type_symlink)}")?

    Ok({})
}

test_file_reader_with_capacity! : () => Try({}, _)
test_file_reader_with_capacity! = || {
    Stdout.line!("\nTesting File.open_reader_with_capacity!:")?

    multi_line_content = "First line\nSecond line\nThird line\n"
    Path.write_utf8!(Path.utf8("test_multiline.txt"), multi_line_content)?

    reader_buf_size : U64
    reader_buf_size = 3
    reader = File.open_reader_with_capacity!(Path.utf8("test_multiline.txt"), reader_buf_size)?
    Stdout.line!("✓ Successfully opened reader with ${reader_buf_size.to_str()} byte capacity")?

    Stdout.line!("\nReading lines from file:")?
    line1_bytes = reader.read_line!()?
    line1_str = Str.from_utf8(line1_bytes) ? |_| LineOneInvalidUtf8
    Stdout.line!("Line 1: ${line1_str}")?

    line2_bytes = reader.read_line!()?
    line2_str = Str.from_utf8(line2_bytes) ? |_| LineTwoInvalidUtf8
    Stdout.line!("Line 2: ${line2_str}")?

    Ok({})
}

test_hard_link! : () => Try({}, _)
test_hard_link! = || {
    Stdout.line!("\nTesting Path.hard_link!:")?

    Path.write_utf8!(Path.utf8("test_original_file.txt"), "Original file content for hard link test")?
    Path.hard_link!(Path.utf8("test_original_file.txt"), Path.utf8("test_link_to_original.txt"))?
    Stdout.line!("✓ Successfully created hard link: test_link_to_original.txt")?

    same_inode = !Try.is_err(Cmd.exec!("test", ["test_original_file.txt", "-ef", "test_link_to_original.txt"]))
    Stdout.line!("Hard link inodes should be equal: ${bool_to_str(same_inode)}")?
    expect_true(same_inode, "hard link should point at the same inode")?

    original_content = Path.read_utf8!(Path.utf8("test_original_file.txt"))?
    link_content = Path.read_utf8!(Path.utf8("test_link_to_original.txt"))?

    if original_content == link_content {
        Stdout.line!("✓ Hard link contains same content as original")
    } else {
        Stderr.line!("✗ Hard link content differs from original")
    }
}

test_file_rename! : () => Try({}, _)
test_file_rename! = || {
    Stdout.line!("\nTesting Path.rename!:")?

    original_name = "test_rename_original.txt"
    new_name = "test_rename_new.txt"
    Path.write_utf8!(Path.utf8(original_name), "Content for rename test")?

    Path.rename!(Path.utf8(original_name), Path.utf8(new_name))?
    Stdout.line!("✓ Successfully renamed ${original_name} to ${new_name}")?

    if Path.exists!(Path.utf8(original_name))? {
        Stderr.line!("✗ Original file ${original_name} still exists after rename")?
    } else {
        Stdout.line!("✓ Original file ${original_name} no longer exists")?
    }

    if Path.is_file!(Path.utf8(new_name))? {
        Stdout.line!("✓ Renamed file ${new_name} exists")?

        content = Path.read_utf8!(Path.utf8(new_name))?
        if content == "Content for rename test" {
            Stdout.line!("✓ Renamed file has correct content")?
        } else {
            Stderr.line!("✗ Renamed file has incorrect content")?
        }
    } else {
        Stderr.line!("✗ Renamed file ${new_name} does not exist")?
    }

    Ok({})
}

test_file_exists! : () => Try({}, _)
test_file_exists! = || {
    Stdout.line!("\nTesting Path.exists!:")?

    filename = "test_exists.txt"
    Path.write_utf8!(Path.utf8(filename), "")?

    if Path.exists!(Path.utf8(filename))? {
        Stdout.line!("✓ Path.exists! returns true for a file that exists")?
    } else {
        Stderr.line!("✗ Path.exists! returned false for a file that exists")?
    }

    Path.delete!(Path.utf8(filename))?

    if Path.exists!(Path.utf8(filename))? {
        Stderr.line!("✗ Path.exists! returned true for a file that does not exist")?
    } else {
        Stdout.line!("✓ Path.exists! returns false for a file that does not exist")?
    }

    Ok({})
}

test_file_size! : () => Try({}, _)
test_file_size! = || {
    Stdout.line!("\nTesting Path.size_in_bytes!:")?

    file_size = Path.size_in_bytes!(Path.utf8("test_bytes.txt"))?
    Stdout.line!("✓ Path.size_in_bytes! returned ${file_size.to_str()} bytes for test_bytes.txt")?

    Ok({})
}

test_is_dir! : () => Try({}, _)
test_is_dir! = || {
    Stdout.line!("\nTesting Path.is_dir!:")?

    if Path.is_dir!(Path.utf8("."))? {
        Stdout.line!("✓ Current directory '.' is recognized as a directory")?
    } else {
        Stderr.line!("✗ Current directory '.' is not recognized as a directory")?
    }

    if Path.is_dir!(Path.utf8("test_bytes.txt"))? {
        Stderr.line!("✗ Regular file is incorrectly recognized as a directory")?
    } else {
        Stdout.line!("✓ Regular file is correctly not recognized as a directory")?
    }

    Ok({})
}

expect_true = |condition, message|
    if condition {
        Ok({})
    } else {
        Err(FailedExpectation(message))
    }

cleanup_test_files! : () => Try({}, _)
cleanup_test_files! = || {
    Stdout.line!("\nCleaning up test files...")?

    test_files = [
        "test_bytes.txt",
        "test_symlink.txt",
        "test_write.json",
        "test_multiline.txt",
        "test_original_file.txt",
        "test_link_to_original.txt",
        "test_rename_new.txt",
    ]

    for filename in test_files {
        Path.delete!(Path.utf8(filename)) ?? {}
    }

    Stdout.line!("✓ Deleted all files.")
}

bool_to_str : Bool -> Str
bool_to_str = |value| if value { "Bool.true" } else { "Bool.false" }

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok(Response.from_status(200).with_body(Str.to_utf8("I am a test.")))
