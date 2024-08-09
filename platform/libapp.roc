app [Model, server] { pf: platform "main.roc" }

import pf.Task exposing [Task]

Model : {}

# Stub file for use during building.
#
# Building just the platform should create a file ./target/release/host
# That file is an executable that runs a webserver that returns "I'm a stub...".
server = {
    init: Task.ok {},
    respond: \_, _ -> Task.ok {
        status: 200,
        headers: [],
        body: Str.toUtf8 "I'm a stub, I should be replaced by the user's Roc app.",
    },
}
