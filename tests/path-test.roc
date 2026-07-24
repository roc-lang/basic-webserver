app [Context, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Stderr
import pf.Path
import pf.Cmd
import pf.Server
import http.Response

Context : {}

program = { init!, respond!, shutdown! }

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            cleanup!() ?? {}
            Stdout.line!("Ran all tests.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            cleanup!() ?? {}
            Stderr.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    Stdout.line!("Testing Path functions...")?
    Stdout.line!("This will create and manipulate test files and directories in the current directory.\n")?

    test_path_creation!()?
    test_file_operations!()?
    test_directory_operations!()?
    test_hard_link!()?
    test_path_rename!()?
    test_path_exists!()?
    test_is_sym_link!()?
    test_path_type!()?

    Stdout.line!("\nI ran all Path function tests.")?

    Ok({})
}

test_path_creation! : () => Try({}, _)
test_path_creation! = || {
    Stdout.line!("Testing Path constructors and pure operations:")?

    path_bytes = [116, 101, 115, 116, 95, 112, 97, 116, 104]
    path_from_bytes = Path.unix_bytes(path_bytes)
    expected_str = "test_path"
    actual_str = Path.display(path_from_bytes)

    portable_path = Path.utf8("test_file.txt")
    filename = Path.filename(portable_path) ?? portable_path
    extension = Path.ext(portable_path) ?? Path.utf8("")

    Stdout.line!("Created path from bytes: ${Path.display(path_from_bytes)}")?
    Stdout.line!("Path.unix_bytes result matches expected: ${bool_to_str(actual_str == expected_str)}")?
    Stdout.line!("Portable UTF-8 path: ${Path.display(portable_path)}")?
    Stdout.line!("Filename: ${Path.display(filename)}")?
    Stdout.line!("Extension: ${Path.display(extension)}")?

    Ok({})
}

test_file_operations! : () => Try({}, _)
test_file_operations! = || {
    Stdout.line!("\nTesting Path file operations:")?

    test_bytes = [72, 101, 108, 108, 111, 44, 32, 80, 97, 116, 104, 33]
    bytes_path = Path.utf8("test_path_bytes.txt")
    Path.write_bytes!(bytes_path, test_bytes)?

    Cmd.exec!("test", ["-e", "test_path_bytes.txt"])?

    read_bytes = Path.read_bytes!(bytes_path)?

    Stdout.line!("Bytes written: ${Str.inspect(test_bytes)}")?
    Stdout.line!("Bytes read: ${Str.inspect(read_bytes)}")?
    Stdout.line!("Bytes match: ${bool_to_str(test_bytes == read_bytes)}")?

    utf8_content = "Hello from Path module! 🚀"
    utf8_path = Path.utf8("test_path_utf8.txt")
    Path.write_utf8!(utf8_path, utf8_content)?

    cat_output = Cmd.new("cat").args(["test_path_utf8.txt"]).exec_output!()?
    read_utf8 = Path.read_utf8!(utf8_path)?

    Stdout.line!("File content via cat: ${cat_output.stdout_utf8}")?
    Stdout.line!("UTF-8 written: ${utf8_content}")?
    Stdout.line!("UTF-8 read: ${read_utf8}")?
    Stdout.line!("UTF-8 content matches: ${bool_to_str(utf8_content == read_utf8)}")?

    json_content = "{\"message\":\"Path test\",\"numbers\":[1,2,3]}"
    json_path = Path.utf8("test_path_json.json")
    Path.write_utf8!(json_path, json_content)?

    read_json = Path.read_utf8!(json_path)?
    contains_message = Str.contains(read_json, "\"message\"")
    contains_numbers = Str.contains(read_json, "\"numbers\"")

    Stdout.line!("JSON content: ${read_json}")?
    Stdout.line!("JSON contains 'message' field: ${bool_to_str(contains_message)}")?
    Stdout.line!("JSON contains 'numbers' field: ${bool_to_str(contains_numbers)}")?

    delete_path = Path.utf8("test_to_delete.txt")
    Path.write_utf8!(delete_path, "This file will be deleted")?
    Cmd.exec!("test", ["-e", "test_to_delete.txt"])?
    Path.delete!(delete_path)?

    exists_after_res = Cmd.exec!("test", ["-e", "test_to_delete.txt"])
    Stdout.line!("File no longer exists: ${bool_to_str(Try.is_err(exists_after_res))}")?

    Ok({})
}

test_directory_operations! : () => Try({}, _)
test_directory_operations! = || {
    Stdout.line!("\nTesting Path directory operations...")?

    single_dir = Path.utf8("test_single_dir")
    Path.create_dir!(single_dir)?
    Cmd.exec!("test", ["-d", "test_single_dir"])?

    nested_dir = Path.utf8("test_parent/test_child/test_grandchild")
    Path.create_all!(nested_dir)?

    find_output = Cmd.new("find").args(["test_parent", "-type", "d"]).exec_output!()?
    dir_count = Str.split_on(find_output.stdout_utf8, "\n").len() - 1

    Stdout.line!("Nested directory structure:\n${find_output.stdout_utf8}\nNumber of directories created: ${dir_count.to_str()}")?

    Path.write_utf8!(Path.utf8("test_single_dir/file1.txt"), "File 1")?
    Path.write_utf8!(Path.utf8("test_single_dir/file2.txt"), "File 2")?
    Path.create_dir!(Path.utf8("test_single_dir/subdir"))?

    ls_contents = Cmd.new("ls").args(["test_single_dir"]).exec_output!()?
    Stdout.line!("Directory contents:\n${ls_contents.stdout_utf8}")?

    empty_dir = Path.utf8("test_empty_dir")
    Path.create_dir!(empty_dir)?
    Cmd.exec!("test", ["-e", "test_empty_dir"])?
    Path.delete_empty!(empty_dir)?

    exists_after_res = Cmd.exec!("test", ["-e", "test_empty_dir"])
    Stdout.line!("Empty dir was deleted: ${bool_to_str(Try.is_err(exists_after_res))}")?

    du_output = Cmd.new("du").args(["-sh", "test_parent"]).exec_output!()?
    Path.delete_all!(Path.utf8("test_parent"))?

    parent_exists_after_res = Cmd.exec!("test", ["-e", "test_parent"])
    Stdout.line!("Size before delete_all: ${du_output.stdout_utf8}\nParent dir no longer exists: ${bool_to_str(Try.is_err(parent_exists_after_res))}")?

    Path.delete_all!(single_dir)?

    Ok({})
}

get_hard_link_count! : Str => Try(Str, _)
get_hard_link_count! = |path_str| {
    ls_l = Cmd.new("ls").args_str(["-l", path_str]).exec_output!()?
    fields = Str.split_on(ls_l.stdout_utf8, " ").drop_if(|field| Str.is_empty(field))
    match List.get(fields, 1) {
        Ok(count) => Ok(count)
        Err(_) => Err(MissingHardLinkCount)
    }
}

first_field : Str -> Str
first_field = |line| {
    fields = Str.split_on(line, " ").drop_if(|field| Str.is_empty(field))
    match List.first(fields) {
        Ok(field) => field
        Err(_) => ""
    }
}

test_hard_link! : () => Try({}, _)
test_hard_link! = || {
    Stdout.line!("\nTesting Path.hard_link!:")?

    original_path = Path.utf8("test_path_original.txt")
    Path.write_utf8!(original_path, "Original content for Path hard link test")?

    hard_link_count_before = get_hard_link_count!("test_path_original.txt")?

    link_path = Path.utf8("test_path_hardlink.txt")
    Path.hard_link!(original_path, link_path)?

    hard_link_count_after = get_hard_link_count!("test_path_original.txt")?
    original_content = Path.read_utf8!(original_path)?
    link_content = Path.read_utf8!(link_path)?

    Stdout.line!("Hard link count before: ${hard_link_count_before}")?
    Stdout.line!("Hard link count after: ${hard_link_count_after}")?
    Stdout.line!("Original content: ${original_content}")?
    Stdout.line!("Link content: ${link_content}")?
    Stdout.line!("Content matches: ${bool_to_str(original_content == link_content)}")?

    ls_li_output =
        Cmd.new("ls")
        .args(["-li", "test_path_hardlink.txt", "test_path_original.txt"])
        .exec_output!()?

    lines = Str.split_on(Str.trim_end(ls_li_output.stdout_utf8), "\n")
    first_line = List.get(lines, 0) ? |_| FirstInodeNotFound
    second_line = List.get(lines, 1) ? |_| SecondInodeNotFound
    first_inode = first_field(first_line)
    second_inode = first_field(second_line)

    Stdout.line!("Inode information:\n${ls_li_output.stdout_utf8}")?
    Stdout.line!("First file inode: [\"${first_inode}\"]")?
    Stdout.line!("Second file inode: [\"${second_inode}\"]")?
    Stdout.line!("Inodes are equal: ${bool_to_str(first_inode == second_inode)}")?

    Ok({})
}

test_path_rename! : () => Try({}, _)
test_path_rename! = || {
    Stdout.line!("\nTesting Path.rename!:")?

    original_path = Path.utf8("test_path_rename_original.txt")
    new_path = Path.utf8("test_path_rename_new.txt")
    test_file_content = "Content for rename test."

    Path.write_utf8!(original_path, test_file_content)?
    Path.rename!(original_path, new_path)?

    if Path.exists!(original_path)? {
        Stderr.line!("✗ Original file still exists after rename")?
    } else {
        Stdout.line!("✓ Original file no longer exists")?
    }

    if Path.is_file!(new_path)? {
        Stdout.line!("✓ Renamed file exists")?

        content = Path.read_utf8!(new_path)?
        if content == test_file_content {
            Stdout.line!("✓ Renamed file has correct content")
        } else {
            Stderr.line!("✗ Renamed file has incorrect content")
        }
    } else {
        Stderr.line!("✗ Renamed file does not exist")
    }
}

test_path_exists! : () => Try({}, _)
test_path_exists! = || {
    Stdout.line!("\nTesting Path.exists!:")?

    filename = Path.utf8("test_path_exists.txt")
    Path.write_utf8!(filename, "This file exists")?

    if Path.exists!(filename)? {
        Stdout.line!("✓ Path.exists! returns true for a file that exists")?
    } else {
        Stderr.line!("✗ Path.exists! returned false for a file that exists")?
    }

    Path.delete!(filename)?

    if Path.exists!(filename)? {
        Stderr.line!("✗ Path.exists! returned true for a file that does not exist")?
    } else {
        Stdout.line!("✓ Path.exists! returns false for a file that does not exist")?
    }

    Ok({})
}

test_is_sym_link! : () => Try({}, _)
test_is_sym_link! = || {
    Stdout.line!("\nTesting Path.is_sym_link!:")?

    regular_file = Path.utf8("test_regular_file.txt")
    Path.write_utf8!(regular_file, "Regular file content")?

    test_dir = Path.utf8("test_directory")
    Path.create_dir!(test_dir)?

    link_to_file = Path.utf8("test_symlink_to_file.txt")
    ln_file_result = Cmd.new("ln").args(["-s", "test_regular_file.txt", "test_symlink_to_file.txt"]).exec_output!()

    link_to_dir = Path.utf8("test_symlink_to_dir")
    ln_dir_result = Cmd.new("ln").args(["-s", "test_directory", "test_symlink_to_dir"]).exec_output!()

    regular_is_symlink = Path.is_sym_link!(regular_file)?
    dir_is_symlink = Path.is_sym_link!(test_dir)?

    file_link_is_symlink =
        match ln_file_result {
            Ok(_) => Path.is_sym_link!(link_to_file)?
            Err(_) => Bool.False
        }

    dir_link_is_symlink =
        match ln_dir_result {
            Ok(_) => Path.is_sym_link!(link_to_dir)?
            Err(_) => Bool.False
        }

    nonexistent_is_symlink = Path.is_sym_link!(Path.utf8("test_nonexistent_path.txt"))?

    Stdout.line!("Regular file is symlink: ${bool_to_str(regular_is_symlink)}")?
    Stdout.line!("Directory is symlink: ${bool_to_str(dir_is_symlink)}")?
    Stdout.line!("File symlink creation successful: ${bool_to_str(!Try.is_err(ln_file_result))}")?
    Stdout.line!("File symlink is symlink: ${bool_to_str(file_link_is_symlink)}")?
    Stdout.line!("Dir symlink creation successful: ${bool_to_str(!Try.is_err(ln_dir_result))}")?
    Stdout.line!("Dir symlink is symlink: ${bool_to_str(dir_link_is_symlink)}")?
    Stdout.line!("Nonexistent path is symlink: ${bool_to_str(nonexistent_is_symlink)}")?

    Ok({})
}

test_path_type! : () => Try({}, _)
test_path_type! = || {
    Stdout.line!("\nTesting Path.type!:")?

    regular_file = Path.utf8("test_type_file.txt")
    Path.write_utf8!(regular_file, "File for type testing")?

    test_dir = Path.utf8("test_type_directory")
    Path.create_dir!(test_dir)?

    symlink_path = Path.utf8("test_type_symlink.txt")
    ln_result = Cmd.new("ln").args(["-s", "test_type_file.txt", "test_type_symlink.txt"]).exec_output!()

    file_type = Path.type!(regular_file)?
    dir_type = Path.type!(test_dir)?
    symlink_type =
        match ln_result {
            Ok(_) => Path.type!(symlink_path)?
            Err(_) => IsFile
        }

    nonexistent_result =
        match Path.type!(Path.utf8("test_nonexistent_type_path.txt")) {
            Ok(_) => "Unexpected success"
            Err(_) => "Expected error"
        }

    Stdout.line!("Regular file type: ${Str.inspect(file_type)}")?
    Stdout.line!("Directory type: ${Str.inspect(dir_type)}")?
    Stdout.line!("Symlink creation successful: ${bool_to_str(!Try.is_err(ln_result))}")?
    Stdout.line!("Symlink type: ${Str.inspect(symlink_type)}")?
    Stdout.line!("Nonexistent path result: ${nonexistent_result}")?

    Ok({})
}

cleanup! : () => Try({}, _)
cleanup! = || {
    Stdout.line!("\nCleaning up test files...")?

    test_paths = [
        "test_path_bytes.txt",
        "test_path_utf8.txt",
        "test_path_json.json",
        "test_path_original.txt",
        "test_path_hardlink.txt",
        "test_path_rename_new.txt",
        "test_regular_file.txt",
        "test_symlink_to_file.txt",
        "test_type_file.txt",
        "test_type_symlink.txt",
        "test_directory",
        "test_symlink_to_dir",
        "test_type_directory",
        "test_single_dir",
    ]

    for path_name in test_paths {
        path = Path.utf8(path_name)
        Path.delete!(path) ?? {}
        Path.delete_all!(path) ?? {}
    }

    ls_after_cleanup_res = Cmd.new("ls").args_str(test_paths).exec_output!()
    Stdout.line!("Files deleted successfully: ${bool_to_str(Try.is_err(ls_after_cleanup_res))}")
}

bool_to_str : Bool -> Str
bool_to_str = |value| if value { "Bool.true" } else { "Bool.false" }


respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str), ..])
respond! = |_request, _state|
    Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8("I am a test."))))

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64), ..])
shutdown! = |_, _| Ok({})
