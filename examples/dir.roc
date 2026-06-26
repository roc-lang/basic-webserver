app [Model, program] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Dir
import pf.Http

# To run this example: check the README.md in this folder

Model : {}

program = { init!, respond! }

init! : {} => Try(Model, [Exit(I64), ..])
init! = |{}| {
    result = || {
        # Create a directory
        Dir.create!("empty-dir")?

        # Create a directory and its parents
        Dir.create_all!("nested-dir/a/b/c")?

        # Create a child directory
        Dir.create!("nested-dir/child")?

        # List the contents of a directory
        paths = Dir.list!("nested-dir")?

        paths_str = Str.join_with(paths, ", ")

        _ = Stdout.line!("The paths in nested-dir are: ${paths_str}")

        # Delete an empty directory
        Dir.delete_empty!("empty-dir")?

        # Delete all directories recursively
        Dir.delete_all!("nested-dir")?

        _ = Stdout.line!("Success!")

        Ok({})
    }

    match result() {
        Ok(_) => Ok({})
        Err(err) => {
            _ = Stderr.line!("Error during directory operations: ${Str.inspect(err)}")
            Err(Exit(1))
        }
    }
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_request, _model|
    Ok({ status: 200, headers: [], body: Str.to_utf8("See example in init! function.") })
