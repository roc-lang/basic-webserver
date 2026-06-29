# Roc Glue Package Nominal Crash Repro

This is a minimal repro for `roc glue` crashing when a platform `requires`
signature references a nominal record type from a package through an exposed
platform module alias.

## Files

```text
pkg/main.roc
pkg/Thing.roc
platform/Api.roc
platform/main.roc
repro_app/main.roc
```

The important shape is:

```roc
# pkg/Thing.roc
Thing :: {
    name : Str,
}.{
    new : Str -> Thing
    new = |name| { name: name }
}

# platform/Api.roc
import pkg.Thing

Api :: [].{
    Thing : Thing.Thing
}

# platform/main.roc
platform "glue-package-nominal-repro"
    requires { main : Api.Thing -> Api.Thing }
    exposes [Api]
    packages {
        pkg: "../pkg/main.roc",
    }
    provides { "roc_main": main_for_host }
    hosted {}
    targets: {}
```

## Repro Commands

From this directory:

```sh
ROC_SRC=/path/to/roc ./repro.sh
```

Or run the commands directly:

```sh
roc check repro_app/main.roc
mkdir -p out
roc glue /path/to/roc/src/glue/src/RustGlue.roc out platform/main.roc
```

With `roc version` reporting `Roc compiler version debug-ca593adf`
(`ca593adfbcb610e50ad41536ec18ac64b5934520`), `roc check` succeeds:

```text
No errors found in ... for repro_app/main.roc
```

But `roc glue` aborts:

```text
thread ... panic: unreachable, node is not a statement tag: .ty_lookup
.../src/canonicalize/NodeStore.zig:743:28: ... in getStatement
.../src/glue/glue.zig:1378:63: ... in nominalRecordInDeclaredOrder
.../src/glue/glue.zig:1317:71: ... in convertNominal
```

## Suggested Issue Title

`roc glue` panics on package nominal record type re-exported through platform module

## Suggested Issue Body

`roc glue` crashes when a platform `requires` signature references a nominal
record type that comes from a package and is re-exported through an exposed
platform module.

Observed with `roc version` reporting `Roc compiler version debug-ca593adf`
(`ca593adfbcb610e50ad41536ec18ac64b5934520`).

The attached minimal repro typechecks, but glue generation panics in
`nominalRecordInDeclaredOrder` after calling `NodeStore.getStatement` on a
non-statement node.

Expected behavior: `roc glue` should either generate glue for this valid
platform or report a normal diagnostic.

Actual behavior: `roc glue` aborts with:

```text
panic: unreachable, node is not a statement tag: .ty_lookup
```

This was found while migrating a platform API to use shared package nominal
types, specifically the official `roc-lang/http` `Request` and `Response`
types.
