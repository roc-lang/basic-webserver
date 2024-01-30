interface InternalDateTime
    exposes [
        DateTime,
        toIso8601Str,
        epochMillisToDateTime,
    ]
    imports []

DateTime : { year : U128, month : U128, day : U128, hours : U128, minutes : U128, seconds : U128 }

toIso8601Str : DateTime -> Str
toIso8601Str = \{ year, month, day, hours, minutes, seconds } ->
    yearStr = yearWithPaddedZeros year
    monthStr = monthWithPaddedZeros month
    dayStr = dayWithPaddedZeros day
    hourStr = hoursWithPaddedZeros hours
    minuteStr = minutesWithPaddedZeros minutes
    secondsStr = secondsWithPaddedZeros seconds

    "\(yearStr)-\(monthStr)-\(dayStr)T\(hourStr):\(minuteStr):\(secondsStr)Z"

yearWithPaddedZeros : U128 -> Str
yearWithPaddedZeros = \year ->
    yearStr = Num.toStr year
    if year < 10 then
        "000\(yearStr)"
    else if year < 100 then
        "00\(yearStr)"
    else if year < 1000 then
        "0\(yearStr)"
    else
        yearStr

monthWithPaddedZeros : U128 -> Str
monthWithPaddedZeros = \month ->
    monthStr = Num.toStr month
    if month < 10 then
        "0\(monthStr)"
    else
        monthStr

dayWithPaddedZeros : U128 -> Str
dayWithPaddedZeros = monthWithPaddedZeros

hoursWithPaddedZeros : U128 -> Str
hoursWithPaddedZeros = monthWithPaddedZeros

minutesWithPaddedZeros : U128 -> Str
minutesWithPaddedZeros = monthWithPaddedZeros

secondsWithPaddedZeros : U128 -> Str
secondsWithPaddedZeros = monthWithPaddedZeros

isLeapYear : U128 -> Bool
isLeapYear = \year ->
    (year % 4 == 0)
    && # divided evenly by 4 unless...
    (
        (year % 100 != 0)
        || # divided by 100 not a leap year
        (year % 400 == 0) # expecpt when also divisible by 400
    )

expect isLeapYear 2000
expect isLeapYear 2012
expect !(isLeapYear 1900)
expect !(isLeapYear 2015)
expect List.map [2023, 1988, 1992, 1996] isLeapYear == [Bool.false, Bool.true, Bool.true, Bool.true]
expect List.map [1700, 1800, 1900, 2100, 2200, 2300, 2500, 2600] isLeapYear == [Bool.false, Bool.false, Bool.false, Bool.false, Bool.false, Bool.false, Bool.false, Bool.false]

daysInMonth : U128, U128 -> U128
daysInMonth = \year, month ->
    if List.contains [1, 3, 5, 7, 8, 10, 12] month then
        31
    else if List.contains [4, 6, 9, 11] month then
        30
    else if month == 2 then
        (if isLeapYear year then 29 else 28)
    else
        0

expect daysInMonth 2023 1 == 31 # January
expect daysInMonth 2023 2 == 28 # February
expect daysInMonth 1996 2 == 29 # February in a leap year
expect daysInMonth 2023 3 == 31 # March
expect daysInMonth 2023 4 == 30 # April
expect daysInMonth 2023 5 == 31 # May
expect daysInMonth 2023 6 == 30 # June
expect daysInMonth 2023 7 == 31 # July
expect daysInMonth 2023 8 == 31 # August
expect daysInMonth 2023 9 == 30 # September
expect daysInMonth 2023 10 == 31 # October
expect daysInMonth 2023 11 == 30 # November
expect daysInMonth 2023 12 == 31 # December

epochMillisToDateTime : U128 -> DateTime
epochMillisToDateTime = \millis ->
    seconds = Num.divTrunc millis 1000
    minutes = Num.divTrunc seconds 60
    hours = Num.divTrunc minutes 60
    day = 1 + Num.divTrunc hours 24
    month = 1
    year = 1970

    epochMillisToDateTimeHelp {
        year,
        month,
        day,
        hours,
        minutes,
        seconds,
    }

epochMillisToDateTimeHelp : DateTime -> DateTime
epochMillisToDateTimeHelp = \current ->

    countDaysInYear = if isLeapYear current.year then 366 else 365
    countDaysInMonth = daysInMonth current.year current.month

    if current.day > countDaysInYear then
        epochMillisToDateTimeHelp {
            year: current.year + 1,
            month: current.month,
            day: current.day - countDaysInYear,
            hours: current.hours - (countDaysInYear * 24),
            minutes: current.minutes - (countDaysInYear * 24 * 60),
            seconds: current.seconds - (countDaysInYear * 24 * 60 * 60),
        }
    else if current.day > countDaysInMonth then
        epochMillisToDateTimeHelp {
            year: current.year,
            month: current.month + 1,
            day: current.day - countDaysInMonth,
            hours: current.hours - (countDaysInMonth * 24),
            minutes: current.minutes - (countDaysInMonth * 24 * 60),
            seconds: current.seconds - (countDaysInMonth * 24 * 60 * 60),
        }
    else
        { current &
            hours: current.hours % 24,
            minutes: current.minutes % 60,
            seconds: current.seconds % 60,
        }


# test last day of 1st year after epoch
expect 
    str = (364 * 24 * 60 * 60 * 1000) |> epochMillisToDateTime |> toIso8601Str
    str == "1970-12-31T00:00:00Z"

# test last day of 1st month after epoch
expect
    str = (30 * 24 * 60 * 60 * 1000) |> epochMillisToDateTime |> toIso8601Str
    str == "1970-01-31T00:00:00Z"

# test 1_700_005_179_053 ms past epoch
expect
    str = 1_700_005_179_053 |> epochMillisToDateTime |> toIso8601Str
    str == "2023-11-14T23:39:39Z"

# test 1000 ms past epoch
expect
    str = 1_000 |> epochMillisToDateTime |> toIso8601Str
    str == "1970-01-01T00:00:01Z"

# test 1_000_000 ms past epoch
expect
    str = 1_000_000 |> epochMillisToDateTime |> toIso8601Str
    str == "1970-01-01T00:16:40Z"

# test 1_000_000_000 ms past epoch
expect
    str = 1_000_000_000 |> epochMillisToDateTime |> toIso8601Str
    str == "1970-01-12T13:46:40Z"

# test 1_600_005_179_000 ms past epoch
expect
    str = 1_600_005_179_000 |> epochMillisToDateTime |> toIso8601Str
    str == "2020-09-13T13:52:59Z"
