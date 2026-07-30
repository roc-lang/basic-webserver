use std::io;
#[cfg(unix)]
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};

pub(crate) fn nanos_since_unix_epoch(time: SystemTime) -> io::Result<i128> {
    match time.duration_since(UNIX_EPOCH) {
        Ok(duration) => i128::try_from(duration.as_nanos())
            .map_err(|_| io::Error::other("timestamp is outside the signed nanosecond range")),
        Err(error) => i128::try_from(error.duration().as_nanos())
            .map(|nanos| -nanos)
            .map_err(|_| io::Error::other("timestamp is outside the signed nanosecond range")),
    }
}

#[cfg(unix)]
pub(crate) fn system_time_from_unix_parts(
    seconds: i64,
    nanoseconds: i64,
) -> io::Result<SystemTime> {
    if !(0..1_000_000_000).contains(&nanoseconds) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "timestamp fractional nanoseconds are not normalized",
        ));
    }

    let total_nanoseconds = i128::from(seconds) * 1_000_000_000 + i128::from(nanoseconds);

    if total_nanoseconds >= 0 {
        let seconds = u64::try_from(total_nanoseconds / 1_000_000_000)
            .map_err(|_| io::Error::other("timestamp seconds are out of range"))?;
        let nanoseconds = u32::try_from(total_nanoseconds % 1_000_000_000)
            .map_err(|_| io::Error::other("timestamp nanoseconds are out of range"))?;

        UNIX_EPOCH
            .checked_add(Duration::new(seconds, nanoseconds))
            .ok_or_else(|| io::Error::other("timestamp is outside the system clock range"))
    } else {
        let magnitude = total_nanoseconds.unsigned_abs();
        let seconds = u64::try_from(magnitude / 1_000_000_000)
            .map_err(|_| io::Error::other("timestamp seconds are out of range"))?;
        let nanoseconds = u32::try_from(magnitude % 1_000_000_000)
            .map_err(|_| io::Error::other("timestamp nanoseconds are out of range"))?;

        UNIX_EPOCH
            .checked_sub(Duration::new(seconds, nanoseconds))
            .ok_or_else(|| io::Error::other("timestamp is outside the system clock range"))
    }
}

#[no_mangle]
pub extern "C" fn hosted_unix_time_now() -> i128 {
    nanos_since_unix_epoch(SystemTime::now())
        .expect("current system time is outside the signed nanosecond range")
}

#[no_mangle]
pub extern "C" fn hosted_sleep_millis(millis: u64) {
    std::thread::sleep(std::time::Duration::from_millis(millis));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unix_time_now_returns_epoch_nanos() {
        assert!(hosted_unix_time_now() > 0);
    }

    #[test]
    fn timestamps_round_trip_on_both_sides_of_the_epoch() {
        let cases = [
            (UNIX_EPOCH, 0),
            (
                UNIX_EPOCH
                    .checked_add(std::time::Duration::new(1, 2))
                    .unwrap(),
                1_000_000_002,
            ),
            (
                UNIX_EPOCH
                    .checked_sub(std::time::Duration::from_millis(500))
                    .unwrap(),
                -500_000_000,
            ),
            (
                UNIX_EPOCH
                    .checked_sub(std::time::Duration::new(1, 1))
                    .unwrap(),
                -1_000_000_001,
            ),
        ];

        for (time, expected) in cases {
            assert_eq!(nanos_since_unix_epoch(time).unwrap(), expected);
        }
    }

    #[cfg(unix)]
    #[test]
    fn unix_parts_require_normalized_nanoseconds() {
        assert!(system_time_from_unix_parts(0, -1).is_err());
        assert!(system_time_from_unix_parts(0, 1_000_000_000).is_err());
    }
}
