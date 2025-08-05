app [Model, init!, respond!] { 
    pf: platform "../platform/main.roc"
}

import pf.Stdout
import pf.Dir
import pf.Path
import pf.Cmd
import pf.Http exposing [Request, Response]

Model : {}

init! : {} => Result Model _
init! = |{}|
    when run_tests!({}) is
        Ok(_) ->
            cleanup_test_dirs!(DirsNeedToExist)?
            Err(Exit(0, "Ran all tests."))
        Err(err) ->
            cleanup_test_dirs!(DirsMaybeExist)?
            Err(Exit(1, "Test run failed:\n\t${Inspect.to_str(err)}"))

run_tests!: {} => Result {} _
run_tests! = |{}|
    Stdout.line!(
        """
        Testing Dir functions...
        This will create and manipulate test directories in the current directory.
        
        """
    )?

    # Test Dir.create!
    test_dir_create!({})?
    
    # Test Dir.create_all!
    test_dir_create_all!({})?
    
    # Test Dir.delete_empty!
    test_dir_delete_empty!({})?

    # Test Dir.delete_all!
    test_dir_delete_all!({})?

    Stdout.line!("\nI ran all Dir function tests.")

test_dir_create! : {} => Result {} _
test_dir_create! = |{}|
    Stdout.line!("Testing Dir.create!:")?

    # Test creating a single directory
    test_dir_name = "test_dir_create"
    Dir.create!(test_dir_name) ? |err| DirCreateFailed(err)
    
    # Verify directory exists using ls
    ls_output =
        Cmd.new("ls")
        |> Cmd.args(["-ld", test_dir_name])
        |> Cmd.output!()
    ls_exit_code = ls_output.status ? |err| LsFailedToGetExitCode(err)
    ls_stdout = Str.from_utf8(ls_output.stdout) ? |_| LsInvalidUtf8
    is_dir = Str.starts_with(ls_stdout, "d")
    
    Stdout.line!(
        """
        Created directory: ${test_dir_name}
        Directory exists: ${Inspect.to_str(ls_exit_code == 0)}
        Is a directory: ${Inspect.to_str(is_dir)}
        Directory listing: ${Str.trim_end(ls_stdout)}
        """
    )?

    # Test creating directory that already exists (should fail)
    create_existing_result = 
        when Dir.create!(test_dir_name) is
            Ok({}) -> "Unexpected success"
            Err(_) -> "Expected error"
    
    Stdout.line!(
        """
        Creating existing directory result: ${create_existing_result}
        """
    )?

    # Test creating directory with non-existent parent (should fail)
    nested_without_parent = "non_existent_parent/test_dir"
    create_nested_result = 
        when Dir.create!(nested_without_parent) is
            Ok({}) -> "Unexpected success"
            Err(_) -> "Expected error"
    
    Stdout.line!(
        """
        Creating directory without parent result: ${create_nested_result}
        """
    )?

    Ok({})

test_dir_create_all! : {} => Result {} _
test_dir_create_all! = |{}|
    Stdout.line!("\nTesting Dir.create_all!:")?

    # Test creating nested directories
    nested_path = "test_parent_all/test_child_all/test_grandchild_all"
    Dir.create_all!(nested_path)?
    
    # Verify nested structure with find
    find_output =
        Cmd.new("find")
        |> Cmd.args(["test_parent_all", "-type", "d"])
        |> Cmd.output!()
    find_stdout = Str.from_utf8(find_output.stdout) ? |_| FindInvalidUtf8
    
    # Count directories created (including the parent)
    dir_lines = Str.split_on(find_stdout, "\n") |> List.keep_if(|line| !Str.is_empty(Str.trim(line)))
    dir_count = List.len(dir_lines)
    
    Stdout.line!(
        """
        Nested directory structure:
        ${find_stdout}
        Number of directories created: ${Num.to_str(dir_count)}
        Expected 3 directories: ${Inspect.to_str(dir_count == 3)}
        """
    )?

    # Test creating directory that already exists with create_all (should succeed)
    Dir.create_all!(nested_path)?
    
    # Verify it still exists
    ls_existing =
        Cmd.new("ls")
        |> Cmd.args(["-ld", nested_path])
        |> Cmd.output!()
    ls_existing_success = ls_existing.status ? |err| LsExistingFailedToGetExitCode(err)
    
    Stdout.line!(
        """
        Creating existing directory with create_all succeeded: ${Inspect.to_str(ls_existing_success == 0)}
        """
    )?

    # Test creating a single directory with create_all
    single_with_create_all = "test_single_with_create_all"
    Dir.create_all!(single_with_create_all)?
    
    ls_single =
        Cmd.new("ls")
        |> Cmd.args(["-ld", single_with_create_all])
        |> Cmd.output!()
    ls_single_success = ls_single.status ? |err| LsSingleFailedToGetExitCode(err)
    
    Stdout.line!(
        """
        Single directory with create_all exists: ${Inspect.to_str(ls_single_success == 0)}
        """
    )?

    Ok({})

test_dir_delete_empty! : {} => Result {} _
test_dir_delete_empty! = |{}|
    Stdout.line!("\nTesting Dir.delete_empty!:")?

    # Create an empty directory
    empty_dir = "test_empty_for_delete"
    Dir.create!(empty_dir)?
    
    # Verify it exists
    ls_before =
        Cmd.new("ls")
        |> Cmd.args(["-ld", empty_dir])
        |> Cmd.output!()
    ls_before_success = ls_before.status ? |err| LsBeforeFailedToGetExitCode(err)
    
    # Delete the empty directory
    Dir.delete_empty!(empty_dir)?
    
    # Verify it's gone
    ls_after =
        Cmd.new("ls")
        |> Cmd.args(["-ld", empty_dir])
        |> Cmd.output!()
    ls_after_success = ls_after.status ? |err| LsAfterFailedToGetExitCode(err)
    
    Stdout.line!(
        """
        Empty directory existed before delete: ${Inspect.to_str(ls_before_success == 0)}
        Empty directory exists after delete: ${Inspect.to_str(ls_after_success == 0)}
        """
    )?

    # Test deleting non-empty directory (should fail)
    non_empty_dir = "test_non_empty_for_delete"
    Dir.create!(non_empty_dir)?
    
    # Add a file to make it non-empty
    Path.write_utf8!("test content", Path.from_str("${non_empty_dir}/test_file.txt"))?
    
    # Try to delete non-empty directory
    delete_non_empty_result = 
        when Dir.delete_empty!(non_empty_dir) is
            Ok({}) -> "Unexpected success"
            Err(_) -> "Expected error"
    
    Stdout.line!(
        """
        Deleting non-empty directory result: ${delete_non_empty_result}
        """
    )?

    # Verify non-empty directory still exists
    ls_non_empty =
        Cmd.new("ls")
        |> Cmd.args(["-ld", non_empty_dir])
        |> Cmd.output!()
    ls_non_empty_success = ls_non_empty.status ? |err| LsNonEmptyFailedToGetExitCode(err)
    
    Stdout.line!(
        """
        Non-empty directory still exists: ${Inspect.to_str(ls_non_empty_success == 0)}
        """
    )?

    # Test deleting non-existent directory (should fail)
    delete_nonexistent_result = 
        when Dir.delete_empty!("non_existent_directory") is
            Ok({}) -> "Unexpected success"
            Err(_) -> "Expected error"
    
    Stdout.line!(
        """
        Deleting non-existent directory result: ${delete_nonexistent_result}
        """
    )?

    Ok({})

test_dir_delete_all! : {} => Result {} _
test_dir_delete_all! = |{}|
    Stdout.line!("\nTesting Dir.delete_all!:")?

    # Create directory with nested structure and files
    complex_dir = "test_complex_for_delete_all"
    Dir.create_all!("${complex_dir}/subdir1/subsubdir")?
    Dir.create_all!("${complex_dir}/subdir2")?
    
    # Add some files
    Path.write_utf8!("file1 content", Path.from_str("${complex_dir}/file1.txt"))?
    Path.write_utf8!("file2 content", Path.from_str("${complex_dir}/subdir1/file2.txt"))?
    Path.write_utf8!("file3 content", Path.from_str("${complex_dir}/subdir1/subsubdir/file3.txt"))?
    Path.write_utf8!("file4 content", Path.from_str("${complex_dir}/subdir2/file4.txt"))?
    
    # Show the structure before deletion
    tree_output =
        Cmd.new("find")
        |> Cmd.args([complex_dir, "-type", "f"])
        |> Cmd.output!()
    tree_stdout = Str.from_utf8(tree_output.stdout) ? |_| TreeInvalidUtf8
    file_lines =
        Str.split_on(tree_stdout, "\n")
        |> List.keep_if(|line| !Str.is_empty(Str.trim(line)))
        |> List.sort_with(
            |str_a, str_b|
                # We just want consistent ordering for testing
                byte_sum_a = Str.to_utf8(str_a) |> List.map(Num.to_u64) |> List.sum
                byte_sum_b = Str.to_utf8(str_b) |> List.map(Num.to_u64) |> List.sum
                 
                if byte_sum_a < byte_sum_b then
                    LT
                else if byte_sum_a > byte_sum_b then
                    GT
                else
                    EQ
        )
    file_count = List.len(file_lines)
    
    Stdout.line!(
        """
        Files in complex directory structure:
        ${tree_stdout}
        Number of files: ${Num.to_str(file_count)}
        """
    )?

    # Delete the entire directory structure
    Dir.delete_all!(complex_dir)?
    
    # Verify it's gone
    ls_after_delete_all =
        Cmd.new("ls")
        |> Cmd.args(["-ld", complex_dir])
        |> Cmd.output!()
    ls_after_delete_all_success = ls_after_delete_all.status ? |err| LsAfterDeleteAllFailedToGetExitCode(err)
    
    Stdout.line!(
        """
        Complex directory exists after delete_all: ${Inspect.to_str(ls_after_delete_all_success == 0)}
        """
    )?

    # Test deleting non-existent directory with delete_all (should fail)
    delete_all_nonexistent_result = 
        when Dir.delete_all!("non_existent_directory_for_delete_all") is
            Ok({}) -> "Unexpected success"
            Err(_) -> "Expected error"
    
    Stdout.line!(
        """
        Deleting non-existent directory with delete_all result: ${delete_all_nonexistent_result}
        """
    )?

    # Clean up the non-empty directory from previous test
    Dir.delete_all!("test_non_empty_for_delete")?

    Ok({})

cleanup_test_dirs! : [DirsNeedToExist, DirsMaybeExist] => Result {} _
cleanup_test_dirs! = |dirs_requirement|
    Stdout.line!("\nCleaning up test directories...")?
    
    test_dirs = [
        "test_dir_create",
        "test_parent_all",
        "test_single_with_create_all",
        "test_non_empty_for_delete",
    ]

    # Clean up directories that exist, ignoring missing ones
    delete_result = List.for_each_try!(test_dirs, |dir_name| 
        # Check if directory exists first
        ls_check =
            Cmd.new("ls")
            |> Cmd.args(["-ld", dir_name])
            |> Cmd.output!()
        if ls_check.status? == 0 then
            # Directory exists, try to delete it
            when Dir.delete_empty!(dir_name) is
                Ok({}) -> Ok({})
                Err(_) -> Dir.delete_all!(dir_name)
        else
            # Directory doesn't exist, which is fine for cleanup
            Ok({})
    )

    when dirs_requirement is
        DirsNeedToExist ->
            delete_result ? |err| DirDeletionFailed(err)
        DirsMaybeExist ->
            Ok({})?
    
    # Verify cleanup by checking remaining directories
    remaining_dirs = List.keep_if_try!(test_dirs, |dir_name|
        ls_check =
            Cmd.new("ls")
            |> Cmd.args(["-ld", dir_name])
            |> Cmd.output!()
        Ok(ls_check.status? == 0)
    ) ? |err| LsCheckFailed(err)
    
    Stdout.line!(
        """
        Cleanup completed. Directories remaining: ${Inspect.to_str(List.len(remaining_dirs))}
        """
    )


respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |_, _|

    Ok(
        {
            status: 200,
            headers: [],
            body: Str.to_utf8("I am a test."),
        },
    )