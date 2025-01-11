app [Model, init!, respond!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Dir
import pf.Env
import pf.Path
import pf.Http exposing [Request, Response]

Model : {}

init! : {} => Result Model _
init! = \{} ->
    # Get current working directory
    cwd =
        Result.map_err(
            Env.cwd!({}),
            \CwdUnavailable -> Exit(1, "Unable to read current working directory"),
        )?

    Stdout.line!("The current working directory is ${Path.display(cwd)}")?

    # Try to set cwd to examples
    Result.map_err(
        Env.set_cwd!(Path.from_str("examples/")),
        \InvalidCwd -> Exit(1, "Unable to set cwd to examples/"),
    )?

    Stdout.line!("Set cwd to examples/")?

    # List contents of examples directory
    paths =
        Result.map_err(
            Dir.list!("./"),
            \DirErr(err) -> Exit(1, "Error reading directory ./:\n\t${Inspect.to_str(err)}"),
        )?

    paths
    |> List.map(Path.display)
    |> Str.join_with(",")
    |> \paths_str -> "The paths are;\n${paths_str}"
    |> Stdout.line!
    |> try

    Ok({})

respond! : Request, Model => Result Response []
respond! = \_, _ ->
    Ok(
        {
            status: 200,
            headers: [],
            body: Str.to_utf8("Logged request"),
        },
    )
