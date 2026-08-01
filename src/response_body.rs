//! Internal response data and fixed-capacity reusable output frames.
//!
//! Ordinary responses retain their existing `Bytes` representation. Native
//! streaming facilities can instead transfer an owned pooled frame through
//! Hyper and recover its vector from `Drop`, without allocating a per-frame
//! ownership adapter.

use bytes::{Buf, Bytes};
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Waker};

#[derive(Debug)]
pub(crate) enum ServerData {
    Bytes(Bytes),
    Pooled(PooledResponseFrame),
}

impl ServerData {
    pub(crate) fn empty() -> Self {
        Self::Bytes(Bytes::new())
    }

    pub(crate) fn is_pooled(&self) -> bool {
        matches!(self, Self::Pooled(_))
    }

    #[cfg(test)]
    pub(crate) fn into_bytes(self) -> Result<Bytes, Self> {
        match self {
            Self::Bytes(bytes) => Ok(bytes),
            pooled => Err(pooled),
        }
    }

    pub(crate) fn split_bytes_to(&mut self, count: usize) -> Self {
        match self {
            Self::Bytes(bytes) => Self::Bytes(bytes.split_to(count)),
            Self::Pooled(_) => panic!("pooled response frames must remain owned while in flight"),
        }
    }
}

impl From<Bytes> for ServerData {
    fn from(bytes: Bytes) -> Self {
        Self::Bytes(bytes)
    }
}

impl From<PooledResponseFrame> for ServerData {
    fn from(frame: PooledResponseFrame) -> Self {
        Self::Pooled(frame)
    }
}

impl Buf for ServerData {
    fn remaining(&self) -> usize {
        match self {
            Self::Bytes(bytes) => bytes.remaining(),
            Self::Pooled(frame) => frame.remaining(),
        }
    }

    fn chunk(&self) -> &[u8] {
        match self {
            Self::Bytes(bytes) => bytes.chunk(),
            Self::Pooled(frame) => frame.chunk(),
        }
    }

    fn advance(&mut self, count: usize) {
        match self {
            Self::Bytes(bytes) => bytes.advance(count),
            Self::Pooled(frame) => frame.advance(count),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct ResponseFramePoolStats {
    pub(crate) slots: usize,
    pub(crate) frame_bytes: usize,
    pub(crate) free_slots: usize,
    pub(crate) in_use_slots: usize,
    pub(crate) high_water_slots: usize,
}

struct PoolState {
    free: Vec<Vec<u8>>,
    slots: usize,
    frame_bytes: usize,
    in_use: usize,
    high_water: usize,
    waiter: Option<Waker>,
}

#[derive(Clone)]
pub(crate) struct ResponseFramePool {
    state: Arc<Mutex<PoolState>>,
}

impl ResponseFramePool {
    pub(crate) fn new(slots: usize, frame_bytes: usize) -> Self {
        assert!(slots > 0, "a response frame pool needs at least one slot");
        assert!(frame_bytes > 0, "response frames must not be empty");
        let mut free = Vec::with_capacity(slots);
        for _ in 0..slots {
            free.push(vec![0; frame_bytes]);
        }
        Self {
            state: Arc::new(Mutex::new(PoolState {
                free,
                slots,
                frame_bytes,
                in_use: 0,
                high_water: 0,
                waiter: None,
            })),
        }
    }

    pub(crate) fn poll_reserve(&self, context: &Context<'_>) -> Poll<ResponseFrameReservation> {
        let mut state = self.state.lock().expect("response frame pool poisoned");
        let Some(buffer) = state.free.pop() else {
            state.waiter = Some(context.waker().clone());
            return Poll::Pending;
        };
        state.in_use += 1;
        state.high_water = state.high_water.max(state.in_use);
        drop(state);
        Poll::Ready(ResponseFrameReservation {
            pool: self.clone(),
            buffer: Some(buffer),
        })
    }

    pub(crate) fn stats(&self) -> ResponseFramePoolStats {
        let state = self.state.lock().expect("response frame pool poisoned");
        ResponseFramePoolStats {
            slots: state.slots,
            frame_bytes: state.frame_bytes,
            free_slots: state.free.len(),
            in_use_slots: state.in_use,
            high_water_slots: state.high_water,
        }
    }

    fn release(&self, mut buffer: Vec<u8>) {
        let mut state = self.state.lock().expect("response frame pool poisoned");
        assert!(buffer.capacity() >= state.frame_bytes);
        buffer.resize(state.frame_bytes, 0);
        state.in_use -= 1;
        state.free.push(buffer);
        if let Some(waiter) = state.waiter.take() {
            waiter.wake();
        }
    }
}

pub(crate) struct ResponseFrameReservation {
    pool: ResponseFramePool,
    buffer: Option<Vec<u8>>,
}

impl ResponseFrameReservation {
    pub(crate) fn output_mut(&mut self) -> &mut [u8] {
        self.buffer
            .as_mut()
            .expect("live response frame reservation owns its buffer")
            .as_mut_slice()
    }

    pub(crate) fn commit(mut self, output_bytes: usize) -> PooledResponseFrame {
        let buffer = self
            .buffer
            .take()
            .expect("live response frame reservation owns its buffer");
        assert!(output_bytes <= buffer.len());
        PooledResponseFrame {
            pool: self.pool.clone(),
            buffer: Some(buffer),
            offset: 0,
            output_bytes,
        }
    }
}

impl Drop for ResponseFrameReservation {
    fn drop(&mut self) {
        if let Some(buffer) = self.buffer.take() {
            self.pool.release(buffer);
        }
    }
}

pub(crate) struct PooledResponseFrame {
    pool: ResponseFramePool,
    buffer: Option<Vec<u8>>,
    offset: usize,
    output_bytes: usize,
}

impl std::fmt::Debug for PooledResponseFrame {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PooledResponseFrame")
            .field("remaining", &self.remaining())
            .field("capacity", &self.buffer.as_ref().map(Vec::capacity))
            .finish()
    }
}

impl Buf for PooledResponseFrame {
    fn remaining(&self) -> usize {
        self.output_bytes - self.offset
    }

    fn chunk(&self) -> &[u8] {
        &self
            .buffer
            .as_ref()
            .expect("live pooled response frame owns its buffer")[self.offset..self.output_bytes]
    }

    fn advance(&mut self, count: usize) {
        assert!(count <= self.remaining());
        self.offset += count;
    }
}

impl Drop for PooledResponseFrame {
    fn drop(&mut self) {
        if let Some(buffer) = self.buffer.take() {
            self.pool.release(buffer);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::task::{Wake, Waker};

    struct CountWake(AtomicUsize);

    impl Wake for CountWake {
        fn wake(self: Arc<Self>) {
            self.0.fetch_add(1, Ordering::Relaxed);
        }

        fn wake_by_ref(self: &Arc<Self>) {
            self.0.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn ready<T>(poll: Poll<T>) -> T {
        match poll {
            Poll::Ready(value) => value,
            Poll::Pending => panic!("reservation unexpectedly pending"),
        }
    }

    #[test]
    fn pooled_frame_returns_capacity_and_wakes_waiter() {
        let pool = ResponseFramePool::new(1, 64);
        let wake_count = Arc::new(CountWake(AtomicUsize::new(0)));
        let waker = Waker::from(Arc::clone(&wake_count));
        let context = Context::from_waker(&waker);
        let mut reservation = ready(pool.poll_reserve(&context));
        reservation.output_mut()[..7].copy_from_slice(b"encoded");
        let mut data = ServerData::from(reservation.commit(7));
        assert_eq!(data.chunk(), b"encoded");
        data.advance(3);
        assert_eq!(data.chunk(), b"oded");
        assert!(pool.poll_reserve(&context).is_pending());
        drop(data);
        assert_eq!(wake_count.0.load(Ordering::Relaxed), 1);
        assert_eq!(
            pool.stats(),
            ResponseFramePoolStats {
                slots: 1,
                frame_bytes: 64,
                free_slots: 1,
                in_use_slots: 0,
                high_water_slots: 1,
            }
        );
    }

    #[test]
    fn abandoned_reservation_returns_capacity() {
        let pool = ResponseFramePool::new(1, 64);
        let waker = futures::task::noop_waker();
        let context = Context::from_waker(&waker);
        drop(ready(pool.poll_reserve(&context)));
        assert_eq!(pool.stats().free_slots, 1);
        assert_eq!(pool.stats().in_use_slots, 0);
    }
}
