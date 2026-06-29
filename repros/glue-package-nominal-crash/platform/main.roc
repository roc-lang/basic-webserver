platform "glue-package-nominal-repro"
    requires { main : Api.Thing -> Api.Thing }
    exposes [Api]
    packages {
        pkg: "../pkg/main.roc",
    }
    provides { "roc_main": main_for_host }
    hosted {}
    targets: {}

import Api

main_for_host : Api.Thing -> Api.Thing
main_for_host = |thing| main(thing)
