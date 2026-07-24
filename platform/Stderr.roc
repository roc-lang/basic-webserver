import IOErr
import Host

## Write diagnostics to the process standard-error stream.
Stderr := [].{

	## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)),
	## followed by a newline.
	##
	## > To write to `stderr` without the newline, see [Stderr.write!].
	line! : Str => Try({}, [StderrErr(IOErr), ..])
	line! = |message|
		match Host.stderr_line!(message) {
			Ok(done) => Ok(done)
			Err(StderrErr(err)) => Err(StderrErr(err))
		}

	## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
	##
	## Most terminals will not actually display strings that are written to them until they receive a newline,
	## so this may appear to do nothing until you write a newline!
	##
	## > To write to `stderr` with a newline at the end, see [Stderr.line!].
	write! : Str => Try({}, [StderrErr(IOErr), ..])
	write! = |message|
		match Host.stderr_write!(message) {
			Ok(done) => Ok(done)
			Err(StderrErr(err)) => Err(StderrErr(err))
		}

	## Write the given bytes to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
	##
	## Most terminals will not actually display content that are written to them until they receive a newline,
	## so this may appear to do nothing until you write a newline!
	write_bytes! : List(U8) => Try({}, [StderrErr(IOErr), ..])
	write_bytes! = |bytes|
		match Host.stderr_write_bytes!(bytes) {
			Ok(done) => Ok(done)
			Err(StderrErr(err)) => Err(StderrErr(err))
		}
}
