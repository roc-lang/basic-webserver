//! Protocol detection and HTTP/1.1 socket progress deadlines.
//!
//! HTTP/2 response progress is stream-scoped and is enforced where the host
//! owns the `h2::SendStream`. HTTP/1.1 has one ordered response at a time, so
//! read and write progress can be enforced directly at the connection I/O
//! boundary without changing application semantics.

use bytes::Bytes;
use std::future::Future;
use std::io;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, ReadBuf};

const H2_PREFACE: &[u8; 24] = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
const READING_HEAD: u8 = 0;
const IN_REQUEST: u8 = 1;
const KEEP_ALIVE: u8 = 2;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Protocol {
    Http1,
    Http2,
}

/// Detect an HTTP/2 prior-knowledge preface without consuming bytes. The
/// deadline is idle rather than total: every newly observed byte resets it.
pub(crate) async fn detect_protocol<S>(
    mut stream: S,
    header_idle_timeout: Duration,
) -> io::Result<(Protocol, PrefixedStream<S>)>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let mut prefix = Vec::with_capacity(H2_PREFACE.len());
    while prefix.len() < H2_PREFACE.len() {
        let mut next = [0u8; 1];
        let count = tokio::time::timeout(header_idle_timeout, stream.read(&mut next))
            .await
            .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "request head timed out"))??;
        if count == 0 {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "connection closed before an HTTP request",
            ));
        }
        prefix.push(next[0]);
        if prefix.as_slice() != &H2_PREFACE[..prefix.len()] {
            return Ok((Protocol::Http1, PrefixedStream::new(stream, prefix)));
        }
    }
    Ok((Protocol::Http2, PrefixedStream::new(stream, prefix)))
}

/// Replays bytes consumed during protocol detection before reading the socket.
pub(crate) struct PrefixedStream<S> {
    stream: S,
    prefix: Bytes,
}

impl<S> PrefixedStream<S> {
    fn new(stream: S, prefix: Vec<u8>) -> Self {
        Self {
            stream,
            prefix: Bytes::from(prefix),
        }
    }
}

impl<S: AsyncRead + Unpin> AsyncRead for PrefixedStream<S> {
    fn poll_read(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if !this.prefix.is_empty() && buffer.remaining() > 0 {
            let count = this.prefix.len().min(buffer.remaining());
            buffer.put_slice(&this.prefix.split_to(count));
            return Poll::Ready(Ok(()));
        }
        Pin::new(&mut this.stream).poll_read(context, buffer)
    }
}

impl<S: AsyncWrite + Unpin> AsyncWrite for PrefixedStream<S> {
    fn poll_write(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &[u8],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.get_mut().stream).poll_write(context, buffer)
    }

    fn poll_flush(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().stream).poll_flush(context)
    }

    fn poll_shutdown(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().stream).poll_shutdown(context)
    }

    fn is_write_vectored(&self) -> bool {
        self.stream.is_write_vectored()
    }

    fn poll_write_vectored(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffers: &[io::IoSlice<'_>],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.get_mut().stream).poll_write_vectored(context, buffers)
    }
}

struct ActivityState {
    phase: AtomicU8,
    response_body_finished: AtomicBool,
}

/// Coordination between Hyper's service/body lifecycle and the HTTP/1.1 I/O
/// adapter. Keep-alive idle time begins only after the response body has
/// finished and Hyper has flushed it.
#[derive(Clone)]
pub(crate) struct Http1Activity {
    state: Arc<ActivityState>,
}

impl Http1Activity {
    pub(crate) fn new() -> Self {
        Self {
            state: Arc::new(ActivityState {
                phase: AtomicU8::new(READING_HEAD),
                response_body_finished: AtomicBool::new(false),
            }),
        }
    }

    pub(crate) fn request_started(&self) {
        self.state
            .response_body_finished
            .store(false, Ordering::Release);
        self.state.phase.store(IN_REQUEST, Ordering::Release);
    }

    pub(crate) fn response_body_finished(&self) {
        self.state
            .response_body_finished
            .store(true, Ordering::Release);
    }

    fn phase(&self) -> u8 {
        self.state.phase.load(Ordering::Acquire)
    }

    fn observed_next_head_bytes(&self) {
        let _ = self.state.phase.compare_exchange(
            KEEP_ALIVE,
            READING_HEAD,
            Ordering::AcqRel,
            Ordering::Acquire,
        );
    }

    fn response_flushed(&self) -> bool {
        if self
            .state
            .response_body_finished
            .swap(false, Ordering::AcqRel)
        {
            self.state.phase.store(KEEP_ALIVE, Ordering::Release);
            true
        } else {
            false
        }
    }
}

/// Tokio I/O wrapper with independent inbound-head, keep-alive, and outbound
/// progress deadlines.
pub(crate) struct Http1Io<S> {
    stream: PrefixedStream<S>,
    activity: Http1Activity,
    header_idle_timeout: Duration,
    keep_alive_idle_timeout: Duration,
    response_idle_timeout: Duration,
    read_phase: u8,
    read_sleep: Pin<Box<tokio::time::Sleep>>,
    write_sleep: Pin<Box<tokio::time::Sleep>>,
    write_waiting: bool,
}

impl<S> Http1Io<S> {
    pub(crate) fn new(
        stream: PrefixedStream<S>,
        activity: Http1Activity,
        header_idle_timeout: Duration,
        keep_alive_idle_timeout: Duration,
        response_idle_timeout: Duration,
    ) -> Self {
        let now = tokio::time::Instant::now();
        Self {
            stream,
            activity,
            header_idle_timeout,
            keep_alive_idle_timeout,
            response_idle_timeout,
            read_phase: READING_HEAD,
            read_sleep: Box::pin(tokio::time::sleep_until(now + header_idle_timeout)),
            write_sleep: Box::pin(tokio::time::sleep_until(now + response_idle_timeout)),
            write_waiting: false,
        }
    }

    fn sync_read_timer(&mut self, phase: u8) {
        if phase == self.read_phase {
            return;
        }
        self.read_phase = phase;
        if let Some(timeout) = self.read_timeout(phase) {
            self.read_sleep
                .as_mut()
                .reset(tokio::time::Instant::now() + timeout);
        }
    }

    fn read_timeout(&self, phase: u8) -> Option<Duration> {
        match phase {
            READING_HEAD => Some(self.header_idle_timeout),
            KEEP_ALIVE => Some(self.keep_alive_idle_timeout),
            IN_REQUEST => None,
            _ => unreachable!("HTTP/1 activity phase is valid"),
        }
    }

    fn reset_read_timer(&mut self, phase: u8) {
        if let Some(timeout) = self.read_timeout(phase) {
            self.read_sleep
                .as_mut()
                .reset(tokio::time::Instant::now() + timeout);
        }
    }

    fn pending_read(&mut self, context: &mut Context<'_>, phase: u8) -> Poll<io::Result<()>> {
        if self.read_timeout(phase).is_some() && self.read_sleep.as_mut().poll(context).is_ready() {
            Poll::Ready(Err(io::Error::new(
                io::ErrorKind::TimedOut,
                if phase == KEEP_ALIVE {
                    "keep-alive connection timed out"
                } else {
                    "request head timed out"
                },
            )))
        } else {
            Poll::Pending
        }
    }

    fn pending_write(&mut self, context: &mut Context<'_>) -> io::Result<Poll<()>> {
        if !self.write_waiting {
            self.write_waiting = true;
            self.write_sleep
                .as_mut()
                .reset(tokio::time::Instant::now() + self.response_idle_timeout);
        }
        if self.write_sleep.as_mut().poll(context).is_ready() {
            Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "response write timed out",
            ))
        } else {
            Ok(Poll::Pending)
        }
    }

    fn write_progress(&mut self) {
        self.write_waiting = false;
        self.write_sleep
            .as_mut()
            .reset(tokio::time::Instant::now() + self.response_idle_timeout);
    }
}

impl<S: AsyncRead + AsyncWrite + Unpin> AsyncRead for Http1Io<S> {
    fn poll_read(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        let phase = this.activity.phase();
        this.sync_read_timer(phase);
        let before = buffer.filled().len();
        match Pin::new(&mut this.stream).poll_read(context, buffer) {
            Poll::Ready(Ok(())) => {
                if buffer.filled().len() > before {
                    this.activity.observed_next_head_bytes();
                    let next_phase = this.activity.phase();
                    this.sync_read_timer(next_phase);
                    this.reset_read_timer(next_phase);
                }
                Poll::Ready(Ok(()))
            }
            Poll::Ready(Err(error)) => Poll::Ready(Err(error)),
            Poll::Pending => this.pending_read(context, phase),
        }
    }
}

impl<S: AsyncRead + AsyncWrite + Unpin> AsyncWrite for Http1Io<S> {
    fn poll_write(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &[u8],
    ) -> Poll<io::Result<usize>> {
        let this = self.get_mut();
        match Pin::new(&mut this.stream).poll_write(context, buffer) {
            Poll::Ready(Ok(written)) => {
                if written > 0 {
                    this.write_progress();
                    // Tokio TCP writes are complete once the kernel accepts
                    // the bytes; Hyper is not required to call poll_flush.
                    if this.activity.response_flushed() {
                        context.waker().wake_by_ref();
                    }
                }
                Poll::Ready(Ok(written))
            }
            Poll::Ready(Err(error)) => Poll::Ready(Err(error)),
            Poll::Pending => match this.pending_write(context) {
                Ok(Poll::Pending) => Poll::Pending,
                Ok(Poll::Ready(())) => unreachable!(),
                Err(error) => Poll::Ready(Err(error)),
            },
        }
    }

    fn poll_flush(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        match Pin::new(&mut this.stream).poll_flush(context) {
            Poll::Ready(Ok(())) => {
                this.write_progress();
                if this.activity.response_flushed() {
                    context.waker().wake_by_ref();
                }
                Poll::Ready(Ok(()))
            }
            Poll::Ready(Err(error)) => Poll::Ready(Err(error)),
            Poll::Pending => match this.pending_write(context) {
                Ok(Poll::Pending) => Poll::Pending,
                Ok(Poll::Ready(())) => unreachable!(),
                Err(error) => Poll::Ready(Err(error)),
            },
        }
    }

    fn poll_shutdown(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().stream).poll_shutdown(context)
    }

    fn is_write_vectored(&self) -> bool {
        self.stream.is_write_vectored()
    }

    fn poll_write_vectored(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffers: &[io::IoSlice<'_>],
    ) -> Poll<io::Result<usize>> {
        let this = self.get_mut();
        match Pin::new(&mut this.stream).poll_write_vectored(context, buffers) {
            Poll::Ready(Ok(written)) => {
                if written > 0 {
                    this.write_progress();
                    if this.activity.response_flushed() {
                        context.waker().wake_by_ref();
                    }
                }
                Poll::Ready(Ok(written))
            }
            Poll::Ready(Err(error)) => Poll::Ready(Err(error)),
            Poll::Pending => match this.pending_write(context) {
                Ok(Poll::Pending) => Poll::Pending,
                Ok(Poll::Ready(())) => unreachable!(),
                Err(error) => Poll::Ready(Err(error)),
            },
        }
    }
}
