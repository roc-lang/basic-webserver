Active `.roc` files in this directory are platform test apps. Keep helper
workflows annotated, use `?` for setup that should fail the test app, and run
them through `./ci/all_tests.sh` so `roc check`, `roc test`, and `roc build` all
exercise the same files.
Most user-facing behavior is tested through examples. Put focused regression
tests here when they do not fit naturally as examples.
