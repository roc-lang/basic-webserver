app [Model, init!, respond!] { pf: platform "main.roc" }

Model : {}

# Stub file for use during building.
#
# Building just the platform should create a file ./target/release/host
# That file is an executable that runs a webserver that returns "I'm a stub...".

init! : {} => Result Model []
init! = \_ -> Ok {}

respond! : _, _ => Result _ []
respond! = \_, _ -> Ok {
        status: Success Ok,
        headers: [],
        body: Str.toUtf8 "I'm a stub, I should be replaced by the user's Roc app.",
    }
