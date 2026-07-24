import Host

DateTime : { year : I128, month : I128, day : I128, hours : I128, minutes : I128, seconds : I128 }

## Read and manipulate UTC timestamps represented as nanoseconds since the Unix
## epoch.
Utc := [].{

	## Get the current UTC time as nanoseconds since the Unix epoch (January 1, 1970).
	now! : () => U128
	now! = || Host.utc_now!()

	## Return nanoseconds since the Unix epoch.
	to_nanos_since_epoch : U128 -> U128
	to_nanos_since_epoch = |nanos| nanos

	## Convert nanoseconds since epoch to a timestamp.
	from_nanos_since_epoch : U128 -> U128
	from_nanos_since_epoch = |nanos| nanos

	## Convert nanoseconds since epoch to milliseconds since epoch.
	to_millis_since_epoch : U128 -> U128
	to_millis_since_epoch = |nanos| nanos // 1_000_000

	## Convert milliseconds since epoch to nanoseconds since epoch.
	from_millis_since_epoch : U128 -> U128
	from_millis_since_epoch = |millis| millis * 1_000_000

	## Calculate the difference between two timestamps in nanoseconds.
	delta_as_nanos : U128, U128 -> U128
	delta_as_nanos = |a, b| if a > b {
		a - b
	} else {
		b - a
	}

	## Calculate the difference between two timestamps in milliseconds.
	delta_as_millis : U128, U128 -> U128
	delta_as_millis = |a, b| {
		nanos = if a > b {
			a - b
		} else {
			b - a
		}
		nanos // 1_000_000
	}

	## Format a UTC timestamp as ISO 8601 seconds, e.g. `2023-11-14T23:39:39Z`.
	to_iso_8601 : U128 -> Str
	to_iso_8601 = |nanos| {
		millis = to_millis_since_epoch(nanos)
		millis_i128 = 
			match U128.to_i128_try(millis) {
				Ok(n) => n
				Err(_) => 0
			}

		datetime_to_iso_8601(epoch_millis_to_datetime(millis_i128))
	}
}

datetime_to_iso_8601 : DateTime -> Str
datetime_to_iso_8601 = |{ year, month, day, hours, minutes, seconds }| {
	year_str = year_with_padded_zeros(year)
	month_str = two_digits(month)
	day_str = two_digits(day)
	hour_str = two_digits(hours)
	minute_str = two_digits(minutes)
	seconds_str = two_digits(seconds)

	"${year_str}-${month_str}-${day_str}T${hour_str}:${minute_str}:${seconds_str}Z"
}

year_with_padded_zeros : I128 -> Str
year_with_padded_zeros = |year| {
	year_str = I128.to_str(year)

	if year < 10 {
		"000${year_str}"
	} else if year < 100 {
		"00${year_str}"
	} else if year < 1000 {
		"0${year_str}"
	} else {
		year_str
	}
}

two_digits : I128 -> Str
two_digits = |n| {
	n_str = I128.to_str(n)

	if n < 10 {
		"0${n_str}"
	} else {
		n_str
	}
}

is_leap_year : I128 -> Bool
is_leap_year = |year|
	(year % 4 == 0) and ((year % 100 != 0) or (year % 400 == 0))

days_in_month : I128, I128 -> I128
days_in_month = |year, month|
	if [1, 3, 5, 7, 8, 10, 12].contains(month) {
		31
	} else if [4, 6, 9, 11].contains(month) {
		30
	} else if month == 2 {
		if is_leap_year(year) {
			29
		} else {
			28
		}
	} else {
		0
	}

epoch_millis_to_datetime : I128 -> DateTime
epoch_millis_to_datetime = |millis| {
	seconds = millis // 1000
	minutes = seconds // 60
	hours = minutes // 60
	day = 1 + hours // 24

	normalize_datetime({
		year: 1970,
		month: 1,
		day,
		hours: hours % 24,
		minutes: minutes % 60,
		seconds: seconds % 60,
	})
}

normalize_datetime : DateTime -> DateTime
normalize_datetime = |current| {
	current_month_days = days_in_month(current.year, current.month)
	previous_month_days = 
		if current.month == 1 {
			days_in_month(current.year - 1, 12)
		} else {
			days_in_month(current.year, current.month - 1)
		}

	if current.day < 1 {
		normalize_datetime({
			..current,
			year: if current.month == 1 {
				current.year - 1
			} else {
				current.year
			},
			month: if current.month == 1 {
				12
			} else {
				current.month - 1
			},
			day: current.day + previous_month_days,
		})
	} else if current.hours < 0 {
		normalize_datetime({ ..current, day: current.day - 1, hours: current.hours + 24 })
	} else if current.minutes < 0 {
		normalize_datetime({ ..current, hours: current.hours - 1, minutes: current.minutes + 60 })
	} else if current.seconds < 0 {
		normalize_datetime({ ..current, minutes: current.minutes - 1, seconds: current.seconds + 60 })
	} else if current.day > current_month_days {
		normalize_datetime({
			..current,
			year: if current.month == 12 {
				current.year + 1
			} else {
				current.year
			},
			month: if current.month == 12 {
				1
			} else {
				current.month + 1
			},
			day: current.day - current_month_days,
		})
	} else {
		current
	}
}

## `is_leap_year` follows Gregorian leap-year rules.
expect {
	is_leap_year(2000)
		and is_leap_year(2012)
			and !is_leap_year(1900)
				and !is_leap_year(2015)
}

## `days_in_month` accounts for leap years.
expect {
	days_in_month(2023, 2) == 28
		and days_in_month(1996, 2) == 29
			and days_in_month(2023, 12) == 31
}

## `epoch_millis_to_datetime` handles representative dates around the epoch.
expect {
	datetime_to_iso_8601(epoch_millis_to_datetime(-1000)) == "1969-12-31T23:59:59Z"
		and datetime_to_iso_8601(epoch_millis_to_datetime(1_000)) == "1970-01-01T00:00:01Z"
			and datetime_to_iso_8601(epoch_millis_to_datetime(1_700_005_179_053)) == "2023-11-14T23:39:39Z"
}

## `to_iso_8601` formats nanosecond timestamps using second precision.
expect {
	Utc.to_iso_8601(Utc.from_millis_since_epoch(1_600_005_179_000)) == "2020-09-13T13:52:59Z"
}
