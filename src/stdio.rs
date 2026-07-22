use core::mem::ManuallyDrop;
use std::io::{self, Write};

use crate::abi::{
    io_err_from_io, roc_host, StderrBytesResult, StderrBytesResultPayload, StderrBytesResultTag,
    StderrUnitResult, StderrUnitResultPayload, StderrUnitResultTag, StdoutBytesResult,
    StdoutBytesResultPayload, StdoutBytesResultTag, StdoutUnitResult, StdoutUnitResultPayload,
    StdoutUnitResultTag,
};
use crate::roc_platform_abi::*;

fn try_stdout_unit_ok() -> StdoutUnitResult {
    StdoutUnitResult {
        payload: StdoutUnitResultPayload { ok: [] },
        tag: StdoutUnitResultTag::Ok,
    }
}

fn try_stdout_unit_err(error: IOErr) -> StdoutUnitResult {
    StdoutUnitResult {
        payload: StdoutUnitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StdoutUnitResultTag::Err,
    }
}

fn try_stdout_bytes_ok() -> StdoutBytesResult {
    StdoutBytesResult {
        payload: StdoutBytesResultPayload { ok: [] },
        tag: StdoutBytesResultTag::Ok,
    }
}

fn try_stdout_bytes_err(error: IOErr) -> StdoutBytesResult {
    StdoutBytesResult {
        payload: StdoutBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StdoutBytesResultTag::Err,
    }
}

fn try_stderr_unit_ok() -> StderrUnitResult {
    StderrUnitResult {
        payload: StderrUnitResultPayload { ok: [] },
        tag: StderrUnitResultTag::Ok,
    }
}

fn try_stderr_unit_err(error: IOErr) -> StderrUnitResult {
    StderrUnitResult {
        payload: StderrUnitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StderrUnitResultTag::Err,
    }
}

fn try_stderr_bytes_ok() -> StderrBytesResult {
    StderrBytesResult {
        payload: StderrBytesResultPayload { ok: [] },
        tag: StderrBytesResultTag::Ok,
    }
}

fn try_stderr_bytes_err(error: IOErr) -> StderrBytesResult {
    StderrBytesResult {
        payload: StderrBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StderrBytesResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_line(message: RocStr) -> StdoutUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        writeln!(stdout, "{}", message.as_str())
    };
    unsafe { message.decref(roc_host) };

    match result {
        Ok(()) => try_stdout_unit_ok(),
        Err(error) => try_stdout_unit_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_write(message: RocStr) -> StdoutUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        write!(stdout, "{}", message.as_str()).and_then(|()| stdout.flush())
    };
    unsafe { message.decref(roc_host) };

    match result {
        Ok(()) => try_stdout_unit_ok(),
        Err(error) => try_stdout_unit_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_write_bytes(bytes: RocListWith<u8, false>) -> StdoutBytesResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        stdout
            .write_all(bytes.as_slice())
            .and_then(|()| stdout.flush())
    };
    unsafe { bytes.decref(roc_host) };

    match result {
        Ok(()) => try_stdout_bytes_ok(),
        Err(error) => try_stdout_bytes_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_line(message: RocStr) -> StderrUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        writeln!(stderr, "{}", message.as_str())
    };
    unsafe { message.decref(roc_host) };

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write(message: RocStr) -> StderrUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        write!(stderr, "{}", message.as_str()).and_then(|()| stderr.flush())
    };
    unsafe { message.decref(roc_host) };

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write_bytes(bytes: RocListWith<u8, false>) -> StderrBytesResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        stderr
            .write_all(bytes.as_slice())
            .and_then(|()| stderr.flush())
    };
    unsafe { bytes.decref(roc_host) };

    match result {
        Ok(()) => try_stderr_bytes_ok(),
        Err(error) => try_stderr_bytes_err(io_err_from_io(&error, roc_host)),
    }
}
