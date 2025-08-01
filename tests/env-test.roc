app [Model, init!, respond!] { 
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Http exposing [Request, Response]
import pf.Env
import pf.Path

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
    Stdout.line!(
        """
        Testing Env module functions...

        Testing Env.cwd!:
        """
    )?
    cwd = Env.cwd!({})?
    Stdout.line!(
        """
        cwd: ${Path.display(cwd)}

        Testing Env.exe_path!:
        """
    )?
    exe_path = Env.exe_path!({})?
    Stdout.line!(
        """
        exe_path: ${Path.display(exe_path)}

        Testing Env.platform!:
        """
    )?
    platform = Env.platform!({})
    Stdout.line!(
        """
        Current platform:${Inspect.to_str(platform)}

        Testing Env.dict!:
        """
    )?
    env_vars = Env.dict!({})
    var_count = Dict.len(env_vars)
    Stdout.line!("Environment variables count: ${Num.to_str(var_count)}")?
    
    some_env_vars = Dict.to_list(env_vars) |> List.take_first(3)
    Stdout.line!(
        """
        Sample environment variables:${Inspect.to_str(some_env_vars)}

        Testing Env.set_cwd!:
        """
    )?
    
    # First get the current directory to restore it later
    original_dir = Env.cwd!({})?
    ls_list = Path.list_dir!(original_dir)?

    dir_list =
        ls_list
        |> List.keep_if_try!(|path| Path.is_dir!(path))?

    first_dir =
        List.first(dir_list)?

    Env.set_cwd!(first_dir)?
    new_cwd = Env.cwd!({})?
    Stdout.line!(
        """
        Changed current directory to: ${Path.display(new_cwd)}

        All tests executed.
        """
    )?

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