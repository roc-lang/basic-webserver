Active `.roc` files in this directory are platform test apps. Keep helper
workflows annotated, use `?` for setup that should fail the test app, and run
them through `./ci/all_tests.sh` so `roc check`, `roc test`, and `roc build` all
exercise the same files.
Currently most things are tested in the examples folder, if something does not fit well as an example we put it here.
