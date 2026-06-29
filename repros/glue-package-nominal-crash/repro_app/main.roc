app [main] {
    pf: platform "../platform/main.roc",
    pkg: "../pkg/main.roc",
}

import pkg.Thing

main : Thing.Thing -> Thing.Thing
main = |thing| thing
