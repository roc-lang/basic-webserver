use core::mem::ManuallyDrop;
use std::io::{self, Read};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use crate::abi::{cmd_io_err_from_io, io_err_from_io, roc_host};
use crate::bounded_gate::{AcquireError, BoundedGate};
use crate::os_str::{os_string_from_raw_borrowed, validate_env_key, RawOsStr};
use crate::roc_platform_abi::*;

type Cmd = HostCmdExecExitCodeArg0;
type CmdExitResult = HostCmdExecExitCodeResult;
type CmdExitResultPayload = HostCmdExecExitCodeResultPayload;
type CmdExitResultTag = HostCmdExecExitCodeResultTag;
type CmdExitError = HostCmdExecExitCodeErr;
type CmdExitErrorPayload = HostCmdExecExitCodeErrPayload;
type CmdExitErrorTag = HostCmdExecExitCodeErrTag;
type CmdOutputResult = HostCmdExecOutputResult;
type CmdOutputResultPayload = HostCmdExecOutputResultPayload;
type CmdOutputResultTag = HostCmdExecOutputResultTag;
type CmdOutputError = HostCmdExecOutputErr;
type CmdOutputErrorPayload = HostCmdExecOutputErrPayload;
type CmdOutputErrorTag = HostCmdExecOutputErrTag;
type CmdOutputFailure = HostCmdExecOutputErrNonZeroExitCode;
type CmdOutputSuccess = HostCmdExecOutputOk;
type CmdOutputLimit = HostCmdExecOutputErrStdoutTooLarge;

const PROCESS_POLL_INTERVAL: Duration = Duration::from_millis(5);
static COMMAND_GATE: BoundedGate = BoundedGate::new(8, 32);

fn copy_native_list(list: &RocList<RawOsStr>) -> io::Result<Vec<std::ffi::OsString>> {
    let mut values = Vec::with_capacity(list.len());
    let mut first_error = None;

    for item in list.as_slice() {
        match os_string_from_raw_borrowed(*item) {
            Ok(value) => values.push(value),
            Err(error) if first_error.is_none() => first_error = Some(error),
            Err(_) => {}
        }
    }

    match first_error {
        Some(error) => Err(error),
        None => Ok(values),
    }
}

fn copy_environment(
    list: &RocList<HostCmdExecExitCodeArg0Envs>,
) -> io::Result<Vec<(std::ffi::OsString, std::ffi::OsString)>> {
    let mut variables = Vec::with_capacity(list.len());
    let mut first_error = None;

    for variable in list.as_slice() {
        let name = os_string_from_raw_borrowed(variable.name);
        let value = os_string_from_raw_borrowed(variable.value);

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

    match first_error {
        Some(error) => Err(error),
        None => Ok(variables),
    }
}

fn cmd_to_std(cmd: &Cmd, roc_host: &RocHost) -> io::Result<Command> {
    // Copy while borrowed, then release the complete hosted argument through
    // its generated recursive decref. A list allocation owns its elements only
    // once even when the list itself has multiple references; consuming every
    // element unconditionally would corrupt another alias.
    let program = os_string_from_raw_borrowed(cmd.program);
    let arguments = copy_native_list(&cmd.args);
    let environment = copy_environment(&cmd.envs);
    unsafe { (*cmd).decref(roc_host) };

    let mut command = Command::new(program?);
    command.args(arguments?);

    if cmd.clear_envs {
        command.env_clear();
    }
    for (name, value) in environment? {
        command.env(name, value);
    }

    // Every child leads a process group on Unix. Limit termination can then
    // clean up descendants that inherited its streams instead of orphaning
    // them. Windows uses a kill-on-close Job Object for the same contract.
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }

    Ok(command)
}

fn deadline(timeout_ms: u64) -> Instant {
    Instant::now()
        .checked_add(Duration::from_millis(timeout_ms.max(1)))
        .unwrap_or_else(Instant::now)
}

fn wait_for_exit(
    child: &mut Child,
    process_tree: &mut ProcessTree,
    deadline: Instant,
) -> Result<ExitStatus, RunError> {
    loop {
        if let Some(status) = child.try_wait().map_err(RunError::Io)? {
            return Ok(status);
        }
        if Instant::now() >= deadline {
            terminate_process_tree(child, process_tree);
            return Err(RunError::Timeout);
        }
        std::thread::sleep(
            PROCESS_POLL_INTERVAL.min(deadline.saturating_duration_since(Instant::now())),
        );
    }
}

#[cfg(unix)]
struct ProcessTree {
    process_group: i32,
}

#[cfg(unix)]
impl ProcessTree {
    fn terminate(&mut self) {
        unsafe {
            libc::kill(-self.process_group, libc::SIGKILL);
        }
    }
}

#[cfg(windows)]
struct ProcessTree {
    job: windows_sys::Win32::Foundation::HANDLE,
}

#[cfg(windows)]
impl ProcessTree {
    fn terminate(&mut self) {
        unsafe {
            windows_sys::Win32::System::JobObjects::TerminateJobObject(self.job, 1);
        }
    }
}

#[cfg(windows)]
impl Drop for ProcessTree {
    fn drop(&mut self) {
        unsafe {
            // KILL_ON_JOB_CLOSE makes cleanup reliable even during unwinding
            // from a host-side error.
            windows_sys::Win32::Foundation::CloseHandle(self.job);
        }
    }
}

fn spawn_managed(command: &mut Command) -> io::Result<(Child, ProcessTree)> {
    #[cfg(unix)]
    {
        let child = command.spawn()?;
        let process_tree = ProcessTree {
            process_group: child.id() as i32,
        };
        Ok((child, process_tree))
    }

    #[cfg(windows)]
    {
        let mut child = command.spawn()?;
        use std::os::windows::io::AsRawHandle;
        use windows_sys::Win32::System::JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
            SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        };

        let job = unsafe { CreateJobObjectW(core::ptr::null(), core::ptr::null()) };
        if job.is_null() {
            let error = io::Error::last_os_error();
            let _ = child.kill();
            let _ = child.wait();
            return Err(error);
        }

        let mut information: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = unsafe { core::mem::zeroed() };
        information.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        let configured = unsafe {
            SetInformationJobObject(
                job,
                JobObjectExtendedLimitInformation,
                (&raw const information).cast(),
                core::mem::size_of_val(&information) as u32,
            )
        };
        let assigned = configured != 0
            && unsafe {
                AssignProcessToJobObject(job, child.as_raw_handle() as *mut core::ffi::c_void) != 0
            };
        if !assigned {
            let error = io::Error::last_os_error();
            unsafe {
                windows_sys::Win32::Foundation::CloseHandle(job);
            }
            let _ = child.kill();
            let _ = child.wait();
            return Err(error);
        }

        Ok((child, ProcessTree { job }))
    }
}

fn terminate_process_tree(child: &mut Child, process_tree: &mut ProcessTree) {
    process_tree.terminate();
    let _ = child.kill();
    let _ = child.wait();
}

#[derive(Debug)]
enum RunError {
    Io(io::Error),
    Timeout,
    Saturated,
    StdoutTooLarge {
        limit_bytes: u64,
        received_at_least: u64,
    },
    StderrTooLarge {
        limit_bytes: u64,
        received_at_least: u64,
    },
}

#[derive(Clone, Copy, Debug)]
enum StreamKind {
    Stdout,
    Stderr,
}

enum ReadResult {
    Complete(Vec<u8>),
    TooLarge {
        limit_bytes: u64,
        received_at_least: u64,
    },
    Io(io::Error),
}

struct ReadMessage {
    kind: StreamKind,
    result: ReadResult,
}

fn read_bounded(
    mut stream: impl Read,
    kind: StreamKind,
    limit_bytes: u64,
    sender: mpsc::Sender<ReadMessage>,
) {
    let mut output = Vec::new();
    let mut received = 0u64;
    let mut chunk = [0u8; 8192];

    let result = loop {
        match stream.read(&mut chunk) {
            Ok(0) => break ReadResult::Complete(output),
            Ok(length) => {
                received = received.saturating_add(length as u64);
                if received > limit_bytes {
                    break ReadResult::TooLarge {
                        limit_bytes,
                        received_at_least: received,
                    };
                }
                output.extend_from_slice(&chunk[..length]);
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => break ReadResult::Io(error),
        }
    };
    let _ = sender.send(ReadMessage { kind, result });
}

struct CapturedOutput {
    status: ExitStatus,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

fn run_captured(
    mut command: Command,
    deadline: Instant,
    stdout_limit: u64,
    stderr_limit: u64,
) -> Result<CapturedOutput, RunError> {
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let (mut child, mut process_tree) = spawn_managed(&mut command).map_err(RunError::Io)?;
    let stdout = match child.stdout.take() {
        Some(stdout) => stdout,
        None => {
            terminate_process_tree(&mut child, &mut process_tree);
            return Err(RunError::Io(io::Error::other("failed to capture stdout")));
        }
    };
    let stderr = match child.stderr.take() {
        Some(stderr) => stderr,
        None => {
            terminate_process_tree(&mut child, &mut process_tree);
            return Err(RunError::Io(io::Error::other("failed to capture stderr")));
        }
    };

    let (sender, receiver) = mpsc::channel();
    let stdout_sender = sender.clone();
    let stdout_reader = std::thread::spawn(move || {
        read_bounded(stdout, StreamKind::Stdout, stdout_limit, stdout_sender)
    });
    let stderr_reader =
        std::thread::spawn(move || read_bounded(stderr, StreamKind::Stderr, stderr_limit, sender));

    let mut status = None;
    let mut stdout = None;
    let mut stderr = None;
    let result = 'run: loop {
        if status.is_none() {
            match child.try_wait() {
                Ok(value) => status = value,
                Err(error) => break Err(RunError::Io(error)),
            }
        }

        while let Ok(message) = receiver.try_recv() {
            match message.result {
                ReadResult::Complete(bytes) => match message.kind {
                    StreamKind::Stdout => stdout = Some(bytes),
                    StreamKind::Stderr => stderr = Some(bytes),
                },
                ReadResult::TooLarge {
                    limit_bytes,
                    received_at_least,
                } => {
                    let error = match message.kind {
                        StreamKind::Stdout => RunError::StdoutTooLarge {
                            limit_bytes,
                            received_at_least,
                        },
                        StreamKind::Stderr => RunError::StderrTooLarge {
                            limit_bytes,
                            received_at_least,
                        },
                    };
                    break 'run Err(error);
                }
                ReadResult::Io(error) => break 'run Err(RunError::Io(error)),
            }
        }

        if status.is_some() && stdout.is_some() && stderr.is_some() {
            break Ok(CapturedOutput {
                status: status.unwrap(),
                stdout: stdout.take().unwrap(),
                stderr: stderr.take().unwrap(),
            });
        }

        if Instant::now() >= deadline {
            break Err(RunError::Timeout);
        }
        std::thread::sleep(
            PROCESS_POLL_INTERVAL.min(deadline.saturating_duration_since(Instant::now())),
        );
    };

    if result.is_err() {
        terminate_process_tree(&mut child, &mut process_tree);
    } else {
        // Command execution never detaches descendants. On normal parent exit,
        // clean up any remaining members before releasing the admission slot.
        process_tree.terminate();
    }
    let _ = stdout_reader.join();
    let _ = stderr_reader.join();
    result
}

#[cfg(not(target_pointer_width = "32"))]
fn make_exit_result(payload: CmdExitResultPayload, tag: CmdExitResultTag) -> CmdExitResult {
    CmdExitResult { payload, tag }
}

#[cfg(target_pointer_width = "32")]
fn make_exit_result(payload: CmdExitResultPayload, tag: CmdExitResultTag) -> CmdExitResult {
    let mut result: CmdExitResult = unsafe { core::mem::zeroed() };
    unsafe {
        (result.payload.as_mut_ptr() as *mut CmdExitResultPayload).write(payload);
    }
    result.tag = tag;
    result
}

#[cfg(not(target_pointer_width = "32"))]
fn make_exit_error(payload: CmdExitErrorPayload, tag: CmdExitErrorTag) -> CmdExitError {
    CmdExitError { payload, tag }
}

#[cfg(target_pointer_width = "32")]
fn make_exit_error(payload: CmdExitErrorPayload, tag: CmdExitErrorTag) -> CmdExitError {
    let mut error: CmdExitError = unsafe { core::mem::zeroed() };
    unsafe {
        (error.payload.as_mut_ptr() as *mut CmdExitErrorPayload).write(payload);
    }
    error.tag = tag;
    error
}

#[cfg(not(target_pointer_width = "32"))]
fn make_output_result(payload: CmdOutputResultPayload, tag: CmdOutputResultTag) -> CmdOutputResult {
    CmdOutputResult { payload, tag }
}

#[cfg(target_pointer_width = "32")]
fn make_output_result(payload: CmdOutputResultPayload, tag: CmdOutputResultTag) -> CmdOutputResult {
    let mut result: CmdOutputResult = unsafe { core::mem::zeroed() };
    unsafe {
        (result.payload.as_mut_ptr() as *mut CmdOutputResultPayload).write(payload);
    }
    result.tag = tag;
    result
}

#[cfg(not(target_pointer_width = "32"))]
fn make_output_error(payload: CmdOutputErrorPayload, tag: CmdOutputErrorTag) -> CmdOutputError {
    CmdOutputError { payload, tag }
}

#[cfg(target_pointer_width = "32")]
fn make_output_error(payload: CmdOutputErrorPayload, tag: CmdOutputErrorTag) -> CmdOutputError {
    let mut error: CmdOutputError = unsafe { core::mem::zeroed() };
    unsafe {
        (error.payload.as_mut_ptr() as *mut CmdOutputErrorPayload).write(payload);
    }
    error.tag = tag;
    error
}

fn try_cmd_exit_ok(value: i32) -> CmdExitResult {
    make_exit_result(
        CmdExitResultPayload {
            ok: ManuallyDrop::new(value),
        },
        CmdExitResultTag::Ok,
    )
}

fn try_cmd_exit_err(error: CmdExitError) -> CmdExitResult {
    make_exit_result(
        CmdExitResultPayload {
            err: ManuallyDrop::new(error),
        },
        CmdExitResultTag::Err,
    )
}

fn cmd_exit_error(error: RunError, roc_host: &RocHost) -> CmdExitError {
    match error {
        RunError::Io(error) => make_exit_error(
            CmdExitErrorPayload {
                failed_to_get_exit_code: ManuallyDrop::new(cmd_io_err_from_io(&error, roc_host)),
            },
            CmdExitErrorTag::FailedToGetExitCode,
        ),
        RunError::Timeout => make_exit_error(
            CmdExitErrorPayload { timeout: [] },
            CmdExitErrorTag::Timeout,
        ),
        RunError::Saturated => make_exit_error(
            CmdExitErrorPayload { saturated: [] },
            CmdExitErrorTag::Saturated,
        ),
        RunError::StdoutTooLarge { .. } | RunError::StderrTooLarge { .. } => unreachable!(),
    }
}

fn try_cmd_output_ok(value: CmdOutputSuccess) -> CmdOutputResult {
    make_output_result(
        CmdOutputResultPayload {
            ok: ManuallyDrop::new(value),
        },
        CmdOutputResultTag::Ok,
    )
}

fn try_cmd_output_err(error: CmdOutputError) -> CmdOutputResult {
    make_output_result(
        CmdOutputResultPayload {
            err: ManuallyDrop::new(error),
        },
        CmdOutputResultTag::Err,
    )
}

fn output_error(error: RunError, roc_host: &RocHost) -> CmdOutputError {
    match error {
        RunError::Io(error) => make_output_error(
            CmdOutputErrorPayload {
                failed_to_get_exit_code: ManuallyDrop::new(io_err_from_io(&error, roc_host)),
            },
            CmdOutputErrorTag::FailedToGetExitCode,
        ),
        RunError::Timeout => make_output_error(
            CmdOutputErrorPayload { timeout: [] },
            CmdOutputErrorTag::Timeout,
        ),
        RunError::Saturated => make_output_error(
            CmdOutputErrorPayload { saturated: [] },
            CmdOutputErrorTag::Saturated,
        ),
        RunError::StdoutTooLarge {
            limit_bytes,
            received_at_least,
        } => make_output_error(
            CmdOutputErrorPayload {
                stdout_too_large: ManuallyDrop::new(CmdOutputLimit {
                    limit_bytes,
                    received_at_least,
                }),
            },
            CmdOutputErrorTag::StdoutTooLarge,
        ),
        RunError::StderrTooLarge {
            limit_bytes,
            received_at_least,
        } => make_output_error(
            CmdOutputErrorPayload {
                stderr_too_large: ManuallyDrop::new(CmdOutputLimit {
                    limit_bytes,
                    received_at_least,
                }),
            },
            CmdOutputErrorTag::StderrTooLarge,
        ),
    }
}

fn nonzero_output_error(
    output: CapturedOutput,
    exit_code: i32,
    roc_host: &RocHost,
) -> CmdOutputError {
    let stdout_bytes = unsafe { RocListWith::<u8, false>::from_slice(&output.stdout, roc_host) };
    let stderr_bytes = unsafe { RocListWith::<u8, false>::from_slice(&output.stderr, roc_host) };
    make_output_error(
        CmdOutputErrorPayload {
            non_zero_exit_code: ManuallyDrop::new(CmdOutputFailure {
                stderr_bytes,
                stdout_bytes,
                exit_code,
            }),
        },
        CmdOutputErrorTag::NonZeroExitCode,
    )
}

#[no_mangle]
pub extern "C" fn hosted_cmd_host_exec_exit_code(cmd: Cmd) -> CmdExitResult {
    let roc_host = roc_host();
    let deadline = deadline(cmd.timeout_ms);
    let mut command = match cmd_to_std(&cmd, roc_host) {
        Ok(command) => command,
        Err(error) => return try_cmd_exit_err(cmd_exit_error(RunError::Io(error), roc_host)),
    };
    let _permit = match COMMAND_GATE.acquire(deadline) {
        Ok(permit) => permit,
        Err(AcquireError::Saturated) => {
            return try_cmd_exit_err(cmd_exit_error(RunError::Saturated, roc_host))
        }
        Err(AcquireError::TimedOut) => {
            return try_cmd_exit_err(cmd_exit_error(RunError::Timeout, roc_host))
        }
    };
    if Instant::now() >= deadline {
        return try_cmd_exit_err(cmd_exit_error(RunError::Timeout, roc_host));
    }

    let (mut child, mut process_tree) = match spawn_managed(&mut command) {
        Ok(child) => child,
        Err(error) => return try_cmd_exit_err(cmd_exit_error(RunError::Io(error), roc_host)),
    };
    match wait_for_exit(&mut child, &mut process_tree, deadline) {
        Ok(status) => {
            process_tree.terminate();
            match status.code() {
                Some(code) => try_cmd_exit_ok(code),
                None => try_cmd_exit_err(cmd_exit_error(
                    RunError::Io(io::Error::other("process was killed by signal")),
                    roc_host,
                )),
            }
        }
        Err(error) => try_cmd_exit_err(cmd_exit_error(error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_host_exec_output(cmd: Cmd) -> CmdOutputResult {
    let roc_host = roc_host();
    let deadline = deadline(cmd.timeout_ms);
    let stdout_limit = cmd.stdout_limit_bytes;
    let stderr_limit = cmd.stderr_limit_bytes;
    let command = match cmd_to_std(&cmd, roc_host) {
        Ok(command) => command,
        Err(error) => return try_cmd_output_err(output_error(RunError::Io(error), roc_host)),
    };
    let _permit = match COMMAND_GATE.acquire(deadline) {
        Ok(permit) => permit,
        Err(AcquireError::Saturated) => {
            return try_cmd_output_err(output_error(RunError::Saturated, roc_host))
        }
        Err(AcquireError::TimedOut) => {
            return try_cmd_output_err(output_error(RunError::Timeout, roc_host))
        }
    };
    if Instant::now() >= deadline {
        return try_cmd_output_err(output_error(RunError::Timeout, roc_host));
    }

    match run_captured(command, deadline, stdout_limit, stderr_limit) {
        Ok(output) => match output.status.code() {
            Some(0) => {
                let stdout_bytes =
                    unsafe { RocListWith::<u8, false>::from_slice(&output.stdout, roc_host) };
                let stderr_bytes =
                    unsafe { RocListWith::<u8, false>::from_slice(&output.stderr, roc_host) };
                try_cmd_output_ok(CmdOutputSuccess {
                    stderr_bytes,
                    stdout_bytes,
                })
            }
            Some(exit_code) => {
                try_cmd_output_err(nonzero_output_error(output, exit_code, roc_host))
            }
            None => try_cmd_output_err(output_error(
                RunError::Io(io::Error::other("process was killed by signal")),
                roc_host,
            )),
        },
        Err(error) => try_cmd_output_err(output_error(error, roc_host)),
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::process::CommandExt;

    #[test]
    fn captured_output_is_bounded_while_reading() {
        let mut command = Command::new("/bin/sh");
        command.arg("-c").arg("printf 123456789").process_group(0);
        let result = run_captured(command, Instant::now() + Duration::from_secs(2), 4, 4);
        assert!(matches!(
            result,
            Err(RunError::StdoutTooLarge {
                limit_bytes: 4,
                received_at_least: 9
            })
        ));
    }

    #[test]
    fn timeout_terminates_a_running_command() {
        let mut command = Command::new("/bin/sh");
        command.arg("-c").arg("sleep 30").process_group(0);
        let started = Instant::now();
        let result = run_captured(command, started + Duration::from_millis(30), 1024, 1024);
        assert!(matches!(result, Err(RunError::Timeout)));
        assert!(started.elapsed() < Duration::from_secs(2));
    }

    #[test]
    fn arguments_are_passed_directly_without_shell_interpretation() {
        let mut command = Command::new("/usr/bin/printf");
        command.arg("%s").arg("$(not-executed)").process_group(0);
        let output =
            run_captured(command, Instant::now() + Duration::from_secs(2), 1024, 1024).unwrap();
        assert_eq!(output.stdout, b"$(not-executed)");
    }
}
