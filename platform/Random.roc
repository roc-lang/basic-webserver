import Host
import IOErr exposing [IOErr]

## Obtain cryptographically secure random bytes from the operating system.
##
## The host returns exactly the requested number of bytes or a typed error.
## Requests are limited to 65,536 bytes so the effect has a fixed allocation
## bound. Call the effect again when an application needs more independent
## random data.
Random := [].{

	## Obtain `count` cryptographically secure random bytes.
	##
	## A zero-byte request succeeds with an empty list. Requests above 65,536
	## bytes fail before allocation.
	bytes! : U64 => Try(
		List(U8),
		[
			EntropyUnavailable(IOErr),
			TooManyBytes({ requested : U64, max : U64 }),
		],
	)
	bytes! = |count| Host.random_bytes!(count)
}
