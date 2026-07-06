import IOErr exposing [IOErr]
import Host

Stdout := [].{
    ## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)),
    ## followed by a newline.
    ##
    ## > To write to `stdout` without the newline, see [Stdout.write!].
    line! : Str => Try({}, [StdoutErr(IOErr), ..])
    line! = |message| Ok(Host.stdout_line!(message)?)

    ## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
    ##
    ## Note that many terminals will not actually display strings that are written to them until they receive a newline,
    ## so this may appear to do nothing until you write a newline!
    ##
    ## > To write to `stdout` with a newline at the end, see [Stdout.line!].
    write! : Str => Try({}, [StdoutErr(IOErr), ..])
    write! = |message| Ok(Host.stdout_write!(message)?)

    ## Write the given bytes to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
    ##
    ## Note that many terminals will not actually display content that is written to them until they receive a newline,
    ## so this may appear to do nothing until you write a newline!
    write_bytes! : List(U8) => Try({}, [StdoutErr(IOErr), ..])
    write_bytes! = |bytes| Ok(Host.stdout_write_bytes!(bytes)?)
}
