use core::mem::ManuallyDrop;
use std::io;

use crate::abi::{cmd_io_err_from_io, cmd_io_err_other, io_err_from_io, io_err_other, roc_host};
use crate::os_str::{os_string_from_raw, validate_env_key, RawOsStr};
use crate::roc_platform_abi::*;

type Cmd = HostCmdExecExitCodeArgs;
type CmdExitResult = HostCmdExecExitCodeResult;
type CmdExitResultPayload = HostCmdExecExitCodeResultPayload;
type CmdExitResultTag = HostCmdExecExitCodeResultTag;
type CmdOutputResult = HostCmdExecOutputResult;
type CmdOutputResultPayload = HostCmdExecOutputResultPayload;
type CmdOutputResultTag = HostCmdExecOutputResultTag;
type CmdOutputError = FailedToGetExitCodeOrNonZeroExitCode;
type CmdOutputErrorPayload = FailedToGetExitCodeOrNonZeroExitCodePayload;
type CmdOutputErrorTag = FailedToGetExitCodeOrNonZeroExitCodeTag;
type CmdOutputFailure = HostCmdExecOutputErrNonZeroExitCode;
type CmdOutputSuccess = HostCmdExecOutputOk;

/// Consume every list element even when one representation is invalid so a
/// rejected foreign-platform value cannot leak later elements.
fn take_native_list(
    list: &RocList<RawOsStr>,
    roc_host: &RocHost,
) -> io::Result<Vec<std::ffi::OsString>> {
    let mut values = Vec::with_capacity(list.len());
    let mut first_error = None;

    for item in list.as_slice() {
        match os_string_from_raw(*item, roc_host) {
            Ok(value) => values.push(value),
            Err(error) if first_error.is_none() => first_error = Some(error),
            Err(_) => {}
        }
    }

    // SAFETY: the hosted call transfers ownership of the list allocation. Each
    // element payload was consumed by `os_string_from_raw` above.
    unsafe { list.decref(roc_host) };

    match first_error {
        Some(error) => Err(error),
        None => Ok(values),
    }
}

/// Consume native environment records while preserving which value is the
/// variable name and which is its value at every layer of the ABI.
fn take_environment(
    list: &RocList<HostCmdExecExitCodeArg0Envs>,
    roc_host: &RocHost,
) -> io::Result<Vec<(std::ffi::OsString, std::ffi::OsString)>> {
    let mut variables = Vec::with_capacity(list.len());
    let mut first_error = None;

    for variable in list.as_slice() {
        let name = os_string_from_raw(variable.name, roc_host);
        let value = os_string_from_raw(variable.value, roc_host);

        match (name, value) {
            (Ok(name), Ok(value)) => {
                if let Err(error) = validate_env_key(name.as_os_str()) {
                    if first_error.is_none() {
                        first_error = Some(error);
                    }
                } else {
                    variables.push((name, value));
                }
            }
            (Err(error), _) | (_, Err(error)) if first_error.is_none() => {
                first_error = Some(error);
            }
            _ => {}
        }
    }

    // SAFETY: the hosted call transfers ownership of the list allocation. Both
    // native-string payloads in every element were consumed above.
    unsafe { list.decref(roc_host) };

    match first_error {
        Some(error) => Err(error),
        None => Ok(variables),
    }
}

fn cmd_to_std(cmd: &Cmd, roc_host: &RocHost) -> io::Result<std::process::Command> {
    // Perform all conversions before propagating an error so every owned field
    // is released even if the program or an earlier argument is invalid.
    let program = os_string_from_raw(cmd.program, roc_host);
    let arguments = take_native_list(&cmd.args, roc_host);
    let environment = take_environment(&cmd.envs, roc_host);

    let mut std_cmd = std::process::Command::new(program?);
    std_cmd.args(arguments?);

    if cmd.clear_envs {
        std_cmd.env_clear();
    }

    for (name, value) in environment? {
        std_cmd.env(name, value);
    }

    Ok(std_cmd)
}

fn try_cmd_exit_ok(value: i32) -> CmdExitResult {
    CmdExitResult {
        payload: CmdExitResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: CmdExitResultTag::Ok,
    }
}

fn try_cmd_exit_err(error: HostIOErr) -> CmdExitResult {
    CmdExitResult {
        payload: CmdExitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: CmdExitResultTag::Err,
    }
}

fn try_cmd_output_ok(value: CmdOutputSuccess) -> CmdOutputResult {
    CmdOutputResult {
        payload: CmdOutputResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: CmdOutputResultTag::Ok,
    }
}

fn try_cmd_output_err(error: CmdOutputError) -> CmdOutputResult {
    CmdOutputResult {
        payload: CmdOutputResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: CmdOutputResultTag::Err,
    }
}

fn cmd_output_nonzero_error(value: CmdOutputFailure) -> CmdOutputError {
    CmdOutputError {
        payload: CmdOutputErrorPayload {
            non_zero_exit_code: ManuallyDrop::new(value),
        },
        tag: CmdOutputErrorTag::NonZeroExitCode,
    }
}

fn cmd_output_failed_to_get_exit_code(error: IOErr) -> CmdOutputError {
    CmdOutputError {
        payload: CmdOutputErrorPayload {
            failed_to_get_exit_code: ManuallyDrop::new(error),
        },
        tag: CmdOutputErrorTag::FailedToGetExitCode,
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_host_exec_exit_code(cmd: Cmd) -> CmdExitResult {
    let roc_host = roc_host();
    let mut std_cmd = match cmd_to_std(&cmd, roc_host) {
        Ok(cmd) => cmd,
        Err(error) => return try_cmd_exit_err(cmd_io_err_from_io(&error, roc_host)),
    };

    match std_cmd.status() {
        Ok(status) => match status.code() {
            Some(code) => try_cmd_exit_ok(code),
            None => try_cmd_exit_err(cmd_io_err_other("process was killed by signal", roc_host)),
        },
        Err(error) => try_cmd_exit_err(cmd_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_host_exec_output(cmd: Cmd) -> CmdOutputResult {
    let roc_host = roc_host();
    let mut std_cmd = match cmd_to_std(&cmd, roc_host) {
        Ok(cmd) => cmd,
        Err(error) => {
            return try_cmd_output_err(cmd_output_failed_to_get_exit_code(io_err_from_io(
                &error, roc_host,
            )))
        }
    };

    match std_cmd.output() {
        Ok(output) => {
            // SAFETY: both Roc lists own copies of the process output buffers.
            let stdout_bytes =
                unsafe { RocListWith::<u8, false>::from_slice(&output.stdout, roc_host) };
            let stderr_bytes =
                unsafe { RocListWith::<u8, false>::from_slice(&output.stderr, roc_host) };

            match output.status.code() {
                Some(0) => try_cmd_output_ok(CmdOutputSuccess {
                    stderr_bytes,
                    stdout_bytes,
                }),
                Some(exit_code) => try_cmd_output_err(cmd_output_nonzero_error(CmdOutputFailure {
                    stderr_bytes,
                    stdout_bytes,
                    exit_code,
                })),
                None => {
                    unsafe {
                        stdout_bytes.decref(roc_host);
                        stderr_bytes.decref(roc_host);
                    }
                    try_cmd_output_err(cmd_output_failed_to_get_exit_code(io_err_other(
                        "process was killed by signal",
                        roc_host,
                    )))
                }
            }
        }
        Err(error) => try_cmd_output_err(cmd_output_failed_to_get_exit_code(io_err_from_io(
            &error, roc_host,
        ))),
    }
}
