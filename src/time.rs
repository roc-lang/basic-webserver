#[no_mangle]
pub extern "C" fn hosted_utc_now() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("time went backwards")
        .as_nanos()
}

#[no_mangle]
pub extern "C" fn hosted_sleep_millis(millis: u64) {
    std::thread::sleep(std::time::Duration::from_millis(millis));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utc_now_returns_epoch_nanos() {
        assert!(hosted_utc_now() > 0);
    }
}
