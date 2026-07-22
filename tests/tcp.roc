app [Model, program] {
    pf: platform "../platform/main.roc",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Stdout
import pf.Http
import pf.Tcp
import http.Response

Model : {}

program = { init!, respond! }

# This test exercises the Tcp module. It requires an echo server listening on
# localhost:8085, e.g. `ncat -e $(which cat) -l 8085`.
init! : () => Try(Model, [Exit(I64), ..])
init! = ||
    match run_tests!() {
        Ok(_) => {
            Stdout.line!("Ran all tests.") ?? {}
            Err(Exit(0))
        }
        Err(err) => {
            Stdout.line!("Test run failed:\n\t${Str.inspect(err)}") ?? {}
            Err(Exit(1))
        }
    }

run_tests! : () => Try({}, _)
run_tests! = || {
    Stdout.line!("Testing Tcp module functions...")?
    Stdout.line!("Note: These tests require a TCP server running on localhost:8085")?
    Stdout.line!("You can start one with: ncat -e `which cat` -l 8085\n")?

    Stdout.line!("Testing Tcp.connect!:")?
    match Tcp.connect!("127.0.0.1", 8085) {
        Ok(stream) => {
            Stdout.line!("✓ Successfully connected to localhost:8085")?
            test_tcp_functions!(stream)
        }
        Err(connect_err) => {
            err_str = Tcp.connect_err_to_str(connect_err)
            Err(ConnectFailed(err_str))
        }
    }
}

test_tcp_functions! : Tcp.Stream => Try({}, _)
test_tcp_functions! = |stream| {
    Stdout.line!("\nTesting Tcp.write!:")?
    hello_bytes = [72, 101, 108, 108, 111, 10] # "Hello\n" in bytes
    stream.write!(hello_bytes)?

    reply_msg = stream.read_line!()?
    Stdout.line!("Echo server reply: ${reply_msg}")?
    Stdout.line!("\n\nTesting Tcp.write_utf8!:")?

    test_message = "Test message from Roc!\n"
    stream.write_utf8!(test_message)?

    reply_msg_utf8 = stream.read_line!()?
    Stdout.line!("Echo server reply: ${reply_msg_utf8}")?
    Stdout.line!("\n\nTesting Tcp.read_up_to!:")?

    # "do not read past meA" in bytes
    do_not_read_bytes = [100, 111, 32, 110, 111, 116, 32, 114, 101, 97, 100, 32, 112, 97, 115, 116, 32, 109, 101, 65]
    stream.write!(do_not_read_bytes)?

    nineteen_bytes = stream.read_up_to!(19)?
    nineteen_bytes_as_str = Str.from_utf8(nineteen_bytes)?
    Stdout.line!("Tcp.read_up_to yielded: '${nineteen_bytes_as_str}'")?
    Stdout.line!("\n\nTesting Tcp.read_exactly!:")?

    stream.write_utf8!("BC")?
    three_bytes = stream.read_exactly!(3)?
    three_bytes_as_str = Str.from_utf8(three_bytes)?
    Stdout.line!("Tcp.read_exactly yielded: '${three_bytes_as_str}'")?
    Stdout.line!("\n\nTesting Tcp.read_until!:")?

    stream.write_utf8!("Line1\nLine2\n")?
    bytes_until = stream.read_until!('\n')?
    bytes_until_as_str = Str.from_utf8(bytes_until)?
    Stdout.line!("Tcp.read_until yielded: '${bytes_until_as_str}'\n")?

    Stdout.line!("Testing Tcp.stream_err_to_str: ${Tcp.stream_err_to_str(StreamNotFound)}\n")?

    Ok({})
}

respond! : Http.Request, Model => Try(Http.Response, [ServerErr(Str), ..])
respond! = |_, _|
    Ok(Response.from_status(200).with_body(Str.to_utf8("I am a test.")))
