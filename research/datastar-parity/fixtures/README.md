# Datastar v1.0.2 protocol fixtures

These byte fixtures pin the stable Datastar client `v1.0.2` wire vocabulary.
The `official/` files are copied byte-for-byte from that release's
[`sdk/test/get-cases`](https://github.com/starfederation/datastar/tree/e24f04d43ca4445d662b4a035e5bfe9ed68de57c/sdk/test/get-cases)
expected outputs. They are MIT-licensed by the upstream project.

The `generic/` cases extend the Datastar fixtures with generic SSE behavior
which the first-party `Sse` module must preserve: clearing a retained event ID,
comments, an empty data line, Unicode, and CRLF parsing. These are derived from
the WHATWG event-stream interpretation algorithm rather than the Go SDK.

Run `python research/datastar-parity/verify_fixtures.py` from the repository
root. The verifier intentionally rejects a missing terminating blank line and
parses LF, CRLF, and CR line endings.
