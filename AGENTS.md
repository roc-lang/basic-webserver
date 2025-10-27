
# General Info

basic-webserver is a Roc platform:

Every Roc application has exactly one platform. That platform provides all the I/O primitives that the application can use; Roc's standard library provides no I/O operations, and the only way for a Roc application to execute functions in other languages is if the platform offers a way to do that.

Applications only interact with the Roc API portion of a platform, but there is also a host portion (written in a different language) that works behind the scenes. The host determines how the program starts, how memory is allocated and deallocated, and how I/O primitives are implemented.

basic-webserver is implemented in Rust and Roc.

# Useful Commands

If you are in a nix dev shell, you can run `buildcmd` to build basic-webserver and `testcmd` to run all tests. Check if you are inside a nix shell with `echo $IN_NIX_SHELL`, enter one with `nix develop`. Or, run a command inside nix with `nix develop -c command`

# Tests

Note that if something is tested in ./examples, it may not have another test in ./tests.

Run an individual test with:
```
roc build --linker=legacy tests/issue_154.roc
TESTS_DIR=tests/ expect ci/expect_scripts/issue_154.exp
```

# Style

- Prefer simple solutions.
- Try to achieve a single source of truth when sensible.