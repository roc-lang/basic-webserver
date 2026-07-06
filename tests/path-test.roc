app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/0.1/6LcdNq2r7xTBwj972ecYWUkMWobJr94yL2NyJpHRAXap.tar.zst",
}

import pf.Stdout
import pf.Stderr
import pf.Path
import pf.File
import pf.Dir
import pf.Cmd
import pf.Http
import http.Response

# NOTE: The Path module re-exports pure path operations from roc-lang/path and
# adds effectful filesystem predicates from the platform host.

Model : {}

program = { init!, respond! }

init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            _ = cleanup!()
            _ = Stdout.line!("Ran all tests.")
            Err(Exit(0))
        }
        Err(err) => {
            _ = cleanup!()
            _ = Stderr.line!("Test run failed:\n\t${Str.inspect(err)}")
            Err(Exit(1))
        }
    }

run_tests! : () => Try(
    {},
    [
        InvalidStr(U64),
        IsDirPath,
        EndsInDots,
        StdoutErr(_),
        FileErr(_),
        DirErr(_),
        PathErr(_),
        ExecFailed(_),
        FailedToGetExitCode(_),
        ..
    ],
)
run_tests! = || {
    Stdout.line!("Testing Path functions...\n")?

    # Test pure path operations from roc-lang/path.
    expected_str = "test_path"
    typed_path : Path.Path
    typed_path = Path.from_str(expected_str)
    roundtrip = Path.display(typed_path)
    to_str_roundtrip = Path.to_str(typed_path)?
    joined_path = Path.join(Path.from_str("test_path"), "nested.txt")
    filename = Path.filename(joined_path)?
    extension = Path.ext(joined_path)?
    raw_bytes_match =
        match Path.to_raw(typed_path) {
            UnixBytes(bytes) => bytes == Str.to_utf8(expected_str)
            WindowsU16s(_) => Bool.False
        }
    Stdout.line!("from_str/display roundtrip matches: ${Str.inspect(roundtrip == expected_str)}")?
    Stdout.line!("to_str roundtrip matches: ${Str.inspect(to_str_roundtrip == expected_str)}")?
    Stdout.line!("joined path: ${Path.display(joined_path)}")?
    Stdout.line!("filename: ${Path.display(filename)}")?
    Stdout.line!("extension: ${Path.display(extension)}")?
    Stdout.line!("raw bytes match: ${Str.inspect(raw_bytes_match)}")?

    # Create a regular file and test Path predicates on it
    File.write_utf8!("test_path_file.txt", "file for path testing")?
    file_path = Path.from_str("test_path_file.txt")

    file_is_file = Path.is_file!(file_path)?
    file_is_dir = Path.is_dir!(file_path)?
    file_type = Path.type!(file_path)?
    Stdout.line!("Regular file is_file: ${Str.inspect(file_is_file)}\nRegular file is_dir: ${Str.inspect(file_is_dir)}\nRegular file type: ${Str.inspect(file_type)}")?

    # Create a directory and test Path predicates on it
    Dir.create!("test_path_dir")?
    dir_path = Path.from_str("test_path_dir")

    dir_is_dir = Path.is_dir!(dir_path)?
    dir_is_file = Path.is_file!(dir_path)?
    dir_type = Path.type!(dir_path)?
    Stdout.line!("Directory is_dir: ${Str.inspect(dir_is_dir)}\nDirectory is_file: ${Str.inspect(dir_is_file)}\nDirectory type: ${Str.inspect(dir_type)}")?

    # Create a symbolic link and test Path.is_sym_link! and Path.type!
    Cmd.exec!("ln", ["-s", "test_path_file.txt", "test_path_symlink.txt"])?
    symlink_path = Path.from_str("test_path_symlink.txt")

    symlink_is_sym_link = Path.is_sym_link!(symlink_path)?
    file_is_sym_link = Path.is_sym_link!(file_path)?
    symlink_type = Path.type!(symlink_path)?
    Stdout.line!("Symlink is_sym_link: ${Str.inspect(symlink_is_sym_link)}\nRegular file is_sym_link: ${Str.inspect(file_is_sym_link)}\nSymlink type: ${Str.inspect(symlink_type)}")?

    # Test type! on a non-existent path (should error)
    nonexistent_result =
        match Path.type!(Path.from_str("test_nonexistent_path.txt")) {
            Ok(_) => "Unexpected success"
            Err(_) => "Expected error"
        }
    Stdout.line!("Nonexistent path type! result: ${nonexistent_result}")?

    Stdout.line!("\nI ran all Path function tests.")?

    Ok({})
}

cleanup! : () => Try({}, _)
cleanup! = || {
    _ = File.delete!("test_path_symlink.txt")
    _ = File.delete!("test_path_file.txt")
    _ = Dir.delete_all!("test_path_dir")
    Stdout.line!("Cleaned up test files.")
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok(Response.from_status(200).with_body(Str.to_utf8("I am a test.")))
