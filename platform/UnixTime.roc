import Host

nanos_per_second : I128
nanos_per_second = 1_000_000_000

## Read and manipulate POSIX wall-clock timestamps.
##
## A timestamp is an instant represented relative to the Unix epoch. It does
## not contain a calendar, time zone, formatting policy, or leap-second model.
## Use a Roc package such as roc-gregorian for those pure computations.
UnixTime := [].{

	## A normalized POSIX timestamp.
	##
	## `nanosecond` is always less than 1,000,000,000. Negative instants use
	## floor-based seconds, so one nanosecond before the epoch is represented as
	## `{ seconds: -1, nanosecond: 999_999_999 }`.
	Timestamp :: { seconds : I64, nanosecond : U32 }.{
		is_eq : _

		## Construct a normalized timestamp.
		from_parts : { seconds : I64, nanosecond : U32 } -> Try(Timestamp, [InvalidNanosecond])
		from_parts = |{ seconds, nanosecond }|
			if nanosecond < 1_000_000_000 {
				Ok(Timestamp.{ seconds, nanosecond })
			} else {
				Err(InvalidNanosecond)
			}

		## Construct a timestamp from signed nanoseconds since the Unix epoch.
		from_nanos_since_epoch : I128 -> Try(Timestamp, [OutOfRange])
		from_nanos_since_epoch = |nanos| {
			seconds_i128 = I128.div_floor_by(nanos, nanos_per_second)
			nanosecond_i128 = I128.mod_by(nanos, nanos_per_second)

			match (I128.to_i64_try(seconds_i128), I128.to_u32_try(nanosecond_i128)) {
				(Ok(seconds), Ok(nanosecond)) => Ok(Timestamp.{ seconds, nanosecond })
				_ => Err(OutOfRange)
			}
		}

		## Return whole seconds since the Unix epoch, rounded toward negative
		## infinity.
		seconds_since_epoch : Timestamp -> I64
		seconds_since_epoch = |timestamp| timestamp.seconds

		## Return the normalized fractional nanoseconds within the timestamp's
		## current second.
		subsecond_nanoseconds : Timestamp -> U32
		subsecond_nanoseconds = |timestamp| timestamp.nanosecond

		## Return signed nanoseconds since the Unix epoch.
		nanos_since_epoch : Timestamp -> I128
		nanos_since_epoch = |timestamp|
			I64.to_i128(timestamp.seconds) * nanos_per_second + U32.to_i128(timestamp.nanosecond)

		## Return `later - earlier` in nanoseconds.
		difference_nanos : Timestamp, Timestamp -> I128
		difference_nanos = |earlier, later|
			nanos_since_epoch(later) - nanos_since_epoch(earlier)
	}

	## Read the current POSIX wall-clock timestamp.
	now! : () => Timestamp
	now! = ||
		match Timestamp.from_nanos_since_epoch(Host.unix_time_now!()) {
			Ok(timestamp) => timestamp
			Err(OutOfRange) => {
				crash "host wall-clock timestamp is outside the UnixTime.Timestamp range"
			}
		}
}

## `from_parts` enforces normalized fractional nanoseconds.
expect {
	UnixTime.Timestamp.from_parts({ seconds: 0, nanosecond: 999_999_999 }) == Ok(
		UnixTime.Timestamp.from_nanos_since_epoch(999_999_999)?,
	) and
		UnixTime.Timestamp.from_parts({ seconds: 0, nanosecond: 1_000_000_000 }) == Err(InvalidNanosecond)
}

## Nanoseconds round-trip on both sides of the Unix epoch.
expect {
	before_epoch = UnixTime.Timestamp.from_nanos_since_epoch(-1)?
	after_epoch = UnixTime.Timestamp.from_nanos_since_epoch(1_000_000_001)?

	before_epoch.seconds_since_epoch() == -1 and
		before_epoch.subsecond_nanoseconds() == 999_999_999 and
			before_epoch.nanos_since_epoch() == -1 and
				after_epoch.seconds_since_epoch() == 1 and
					after_epoch.subsecond_nanoseconds() == 1 and
						after_epoch.nanos_since_epoch() == 1_000_000_001
}

## Timestamp differences preserve direction.
expect {
	earlier = UnixTime.Timestamp.from_nanos_since_epoch(-1)?
	later = UnixTime.Timestamp.from_nanos_since_epoch(1)?

	UnixTime.Timestamp.difference_nanos(earlier, later) == 2 and
		UnixTime.Timestamp.difference_nanos(later, earlier) == -2
}

## The timestamp range is intentionally bounded by signed 64-bit seconds.
expect {
	first_out_of_range = 9_223_372_036_854_775_808_000_000_000
	UnixTime.Timestamp.from_nanos_since_epoch(first_out_of_range) == Err(OutOfRange)
}
