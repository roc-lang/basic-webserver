use std::sync::{Mutex, MutexGuard, TryLockError};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CapabilityLockError {
    Busy,
    Poisoned,
}

pub(crate) fn try_lock<T>(resource: &Mutex<T>) -> Result<MutexGuard<'_, T>, CapabilityLockError> {
    match resource.try_lock() {
        Ok(guard) => Ok(guard),
        Err(TryLockError::WouldBlock) => Err(CapabilityLockError::Busy),
        Err(TryLockError::Poisoned(_)) => Err(CapabilityLockError::Poisoned),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Barrier};

    #[test]
    fn concurrent_use_saturates_instead_of_aliasing_mutable_state() {
        let resource = Arc::new(Mutex::new(0_u8));
        let locked = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));

        let worker_resource = Arc::clone(&resource);
        let worker_locked = Arc::clone(&locked);
        let worker_release = Arc::clone(&release);
        let worker = std::thread::spawn(move || {
            let _guard = worker_resource.lock().unwrap();
            worker_locked.wait();
            worker_release.wait();
        });

        locked.wait();
        assert_eq!(try_lock(&resource).unwrap_err(), CapabilityLockError::Busy);
        release.wait();
        worker.join().unwrap();
        assert!(try_lock(&resource).is_ok());
    }

    #[test]
    fn poisoned_state_is_rejected() {
        let resource = Arc::new(Mutex::new(0_u8));
        let worker_resource = Arc::clone(&resource);
        let worker = std::thread::spawn(move || {
            let _guard = worker_resource.lock().unwrap();
            panic!("poison test resource");
        });

        assert!(worker.join().is_err());
        assert_eq!(
            try_lock(&resource).unwrap_err(),
            CapabilityLockError::Poisoned
        );
    }
}
