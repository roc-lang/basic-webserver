use core::mem::ManuallyDrop;

use crate::abi::{
    cmd_io_err_from_io, cmd_io_err_other, decref_roc_str_list, io_err_from_io, io_err_other,
    roc_host, Cmd, CmdExitResult, CmdExitResultPayload, CmdExitResultTag, CmdOutputFailure,
    CmdOutputFailureResult, CmdOutputFailureResultPayload, CmdOutputFailureResultTag,
    CmdOutputResult, CmdOutputResultPayload, CmdOutputResultTag, CmdOutputSuccess,
};
use crate::roc_platform_abi::*;

trait CommandEnvValue {
    fn command_env_str(&self) -> &str;
}

impl CommandEnvValue for RocStr {
    fn command_env_str(&self) -> &str {
        self.as_str()
    }
}

fn env_pairs<T: CommandEnvValue>(envs: &[T]) -> impl Iterator<Item = (&str, &str)> {
    envs.chunks(2).filter_map(|chunk| match chunk {
        [key, value] => Some((key.command_env_str(), value.command_env_str())),
        _ => None,
    })
}

fn decref_host_cmd_arg(cmd: &Cmd, roc_host: &RocHost) {
    decref_roc_str_list(&cmd.args, roc_host);
    decref_roc_str_list(&cmd.envs, roc_host);
    // SAFETY: hosted arguments transfer ownership to the host.
    unsafe { cmd.program.decref(roc_host) };
}

fn cmd_to_std(cmd: &Cmd) -> std::process::Command {
    let mut std_cmd = std::process::Command::new(cmd.program.as_str());

    for arg in cmd.args.as_slice() {
        std_cmd.arg(arg.as_str());
    }

    if cmd.clear_envs {
        std_cmd.env_clear();
    }

    for (key, value) in env_pairs(cmd.envs.as_slice()) {
        std_cmd.env(key, value);
    }

    std_cmd
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

fn try_cmd_output_err(error: CmdOutputFailureResult) -> CmdOutputResult {
    CmdOutputResult {
        payload: CmdOutputResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: CmdOutputResultTag::Err,
    }
}

fn try_cmd_output_failure_ok(value: CmdOutputFailure) -> CmdOutputFailureResult {
    CmdOutputFailureResult {
        payload: CmdOutputFailureResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: CmdOutputFailureResultTag::Ok,
    }
}

fn try_cmd_output_failure_err(error: crate::abi::HostIOErrType) -> CmdOutputFailureResult {
    CmdOutputFailureResult {
        payload: CmdOutputFailureResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: CmdOutputFailureResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_host_exec_exit_code(cmd: Cmd) -> CmdExitResult {
    let roc_host = roc_host();
    let mut std_cmd = cmd_to_std(&cmd);
    decref_host_cmd_arg(&cmd, roc_host);

    match std_cmd.status() {
        Ok(status) => match status.code() {
            Some(code) => try_cmd_exit_ok(code),
            None => try_cmd_exit_err(cmd_io_err_other("Process was killed by signal", roc_host)),
        },
        Err(error) => try_cmd_exit_err(cmd_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_host_exec_output(cmd: Cmd) -> CmdOutputResult {
    let roc_host = roc_host();
    let mut std_cmd = cmd_to_std(&cmd);
    decref_host_cmd_arg(&cmd, roc_host);

    match std_cmd.output() {
        Ok(output) => {
            // SAFETY: both lists own copies of the process output buffers.
            let stdout_bytes =
                unsafe { RocListWith::<u8, false>::from_slice(&output.stdout, roc_host) };
            let stderr_bytes =
                unsafe { RocListWith::<u8, false>::from_slice(&output.stderr, roc_host) };

            match output.status.code() {
                Some(0) => try_cmd_output_ok(CmdOutputSuccess {
                    stderr_bytes,
                    stdout_bytes,
                }),
                Some(exit_code) => {
                    try_cmd_output_err(try_cmd_output_failure_ok(CmdOutputFailure {
                        stderr_bytes,
                        stdout_bytes,
                        exit_code,
                    }))
                }
                None => {
                    unsafe { stdout_bytes.decref(roc_host) };
                    unsafe { stderr_bytes.decref(roc_host) };
                    try_cmd_output_err(try_cmd_output_failure_err(io_err_other(
                        "Process was killed by signal",
                        roc_host,
                    )))
                }
            }
        }
        Err(error) => {
            try_cmd_output_err(try_cmd_output_failure_err(io_err_from_io(&error, roc_host)))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    impl CommandEnvValue for String {
        fn command_env_str(&self) -> &str {
            self.as_str()
        }
    }

    #[test]
    fn env_pairs_uses_complete_key_value_pairs_only() {
        let values = vec![
            "FIRST".to_string(),
            "1".to_string(),
            "SECOND".to_string(),
            "2".to_string(),
            "TRAILING_KEY".to_string(),
        ];

        let pairs: Vec<_> = env_pairs(&values).collect();

        assert_eq!(pairs, vec![("FIRST", "1"), ("SECOND", "2")]);
    }
}
