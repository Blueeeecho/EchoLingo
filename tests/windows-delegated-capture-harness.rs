//! A Windows-only fixture host importing both exact production input modules.
//! stdin controls lifecycle only; all captured input comes from actual SendInput.
#[path = "../src-tauri/src/windows_capture_input.rs"]
mod windows_capture_input;
#[path = "../src-tauri/src/windows_visibility.rs"]
mod windows_visibility;

#[cfg(windows)]
mod desktop {
    use super::windows_capture_input as bridge;
    use super::windows_visibility as observer;
    use std::ffi::c_void;
    use std::io::{self, BufRead, Read, Write};
    use std::ops::{Deref, DerefMut};
    use std::os::windows::io::AsRawHandle;
    use std::os::windows::process::CommandExt;
    use std::path::PathBuf;
    use std::process::{Command, Stdio};
    use std::thread;
    use std::time::{Duration, Instant};
    // A private kill-on-close job prevents an aborted fixture controller from
    // leaving its own helper behind. No foreign processes enter this job.
    #[repr(C)]
    #[derive(Default)]
    struct BasicLimits {
        process_time: i64,
        job_time: i64,
        flags: u32,
        min: usize,
        max: usize,
        active: u32,
        affinity: usize,
        priority: u32,
        scheduling: u32,
    }
    #[repr(C)]
    #[derive(Default)]
    struct ExtendedLimits {
        basic: BasicLimits,
        io: [u64; 6],
        process_memory: usize,
        job_memory: usize,
        peak_process: usize,
        peak_job: usize,
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn CreateJobObjectW(attributes: *mut c_void, name: *const u16) -> *mut c_void;
        fn SetInformationJobObject(
            job: *mut c_void,
            kind: i32,
            data: *const c_void,
            length: u32,
        ) -> i32;
        fn AssignProcessToJobObject(job: *mut c_void, process: *mut c_void) -> i32;
        fn CloseHandle(handle: *mut c_void) -> i32;
    }
    struct Job(*mut c_void);
    impl Job {
        fn new() -> Result<Self, String> {
            let job = Self(unsafe { CreateJobObjectW(std::ptr::null_mut(), std::ptr::null()) });
            if job.0.is_null() {
                return Err("FIXTURE_CHILD_JOB_CREATE".into());
            }
            let mut limits = ExtendedLimits::default();
            limits.basic.flags = 0x2000;
            if unsafe {
                SetInformationJobObject(
                    job.0,
                    9,
                    (&limits as *const ExtendedLimits).cast(),
                    std::mem::size_of::<ExtendedLimits>() as u32,
                )
            } == 0
            {
                return Err("FIXTURE_CHILD_JOB_LIMIT".into());
            }
            Ok(job)
        }
        fn bind(&self, child: &std::process::Child) -> Result<(), String> {
            if unsafe { AssignProcessToJobObject(self.0, child.as_raw_handle()) } == 0 {
                return Err("FIXTURE_CHILD_JOB_ASSIGN".into());
            }
            Ok(())
        }
    }
    impl Drop for Job {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe {
                    CloseHandle(self.0);
                }
            }
        }
    }
    struct OwnedChild<'a> {
        child: std::process::Child,
        session: &'a mut bridge::Session,
    }
    impl Deref for OwnedChild<'_> {
        type Target = std::process::Child;
        fn deref(&self) -> &Self::Target {
            &self.child
        }
    }
    impl DerefMut for OwnedChild<'_> {
        fn deref_mut(&mut self) -> &mut Self::Target {
            &mut self.child
        }
    }
    impl Drop for OwnedChild<'_> {
        fn drop(&mut self) {
            self.session.close();
            if self.child.try_wait().ok().flatten().is_none() {
                let _ = self.child.kill();
                let _ = self.child.wait();
            }
        }
    }
    fn emit(value: &str) -> Result<(), String> {
        println!("{value}");
        io::stdout().flush().map_err(|_| "HOST_PIPE_WRITE".into())
    }
    fn collect(reader: impl Read) -> (String, bool) {
        let mut bytes = Vec::new();
        let result = reader.take(32 * 1024 * 1024 + 1).read_to_end(&mut bytes);
        let valid = result.is_ok() && bytes.len() <= 32 * 1024 * 1024;
        (String::from_utf8(bytes).unwrap_or_default(), valid)
    }
    pub fn run() -> Result<(), String> {
        let args: Vec<_> = std::env::args_os().collect();
        if args.len() != 3 {
            return Err("USAGE_HELPER_ASSEMBLY_PATHS".into());
        }
        let helper = PathBuf::from(&args[1])
            .canonicalize()
            .map_err(|_| "HELPER_PATH")?;
        let assembly = PathBuf::from(&args[2])
            .canonicalize()
            .map_err(|_| "ASSEMBLY_PATH")?;
        if !helper.is_file() || !assembly.is_file() {
            return Err("HELPER_FILE_REQUIRED".into());
        }
        let shell = PathBuf::from(std::env::var_os("SystemRoot").ok_or("WINDOWS_DIRECTORY")?)
            .join("System32/WindowsPowerShell/v1.0/powershell.exe");
        let job = Job::new()?;
        let _receiver = observer::start()?;
        observer::disarm();
        emit(&format!("{{\"event\":\"host\",\"hostProcessId\":{},\"productionModulesImported\":true,\"outsideClickGateDisarmed\":true}}",std::process::id()))?;
        let mut generation = 0;
        for command in io::stdin().lock().lines() {
            let command = command.map_err(|_| "HOST_PIPE_READ")?;
            if command == "shutdown" {
                break;
            }
            if command != "capture" {
                return Err("LIFECYCLE_COMMAND_REQUIRED".into());
            }
            generation += 1;
            let mut session = bridge::Session::begin()?;
            let host_thread = session.thread();
            let started = Instant::now();
            let mut child = OwnedChild {
                child: Command::new(&shell)
                    .args(["-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File"])
                    .arg(&helper)
                    .args(["-Mode", "capture-image", "-NativeAssemblyPath"])
                    .arg(&assembly)
                    .arg("-CaptureHostThreadId")
                    .arg(session.thread().to_string())
                    .arg("-CaptureHostToken")
                    .arg(session.token().to_string())
                    .arg("-PerformanceDiagnostics")
                    .stdin(Stdio::null())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::piped())
                    .creation_flags(0x08000000)
                    .spawn()
                    .map_err(|_| "HELPER_SPAWN_FAILED")?,
                session: &mut session,
            };
            job.bind(&child)?;
            let child_pid = child.id();
            child.session.bind_child(child_pid);
            let output = child.stdout.take().ok_or("HELPER_STDOUT")?;
            let error = child.stderr.take().ok_or("HELPER_STDERR")?;
            let output = thread::spawn(move || collect(output));
            let error = thread::spawn(move || collect(error));
            emit(&format!("{{\"event\":\"child\",\"generation\":{generation},\"helperProcessId\":{},\"hostProcessId\":{}}}",child.id(),std::process::id()))?;
            let mut killed = false;
            let status = loop {
                if let Some(status) = child.try_wait().map_err(|_| "HELPER_WAIT_FAILED")? {
                    break status;
                }
                if started.elapsed() > Duration::from_secs(45) {
                    child.session.close();
                    let _ = child.kill();
                    killed = true;
                    break child.wait().map_err(|_| "HELPER_TIMEOUT_WAIT")?;
                }
                thread::sleep(Duration::from_millis(5));
            };
            child.session.close();
            let (reply, valid) = output.join().map_err(|_| "HELPER_STDOUT_THREAD")?;
            let (stderr, _) = error.join().map_err(|_| "HELPER_STDERR_THREAD")?;
            // Only the private pipe receives the original helper result; the PS
            // controller whitelists diagnostics and never logs captured pixels.
            if valid && reply.trim().starts_with('{') && reply.trim().ends_with('}') {
                emit(reply.trim())?;
            } else {
                emit("{\"ok\":false,\"error\":\"HELPER_REPLY_MISSING_OR_INVALID\"}")?;
            }
            emit(&format!("{{\"event\":\"closed\",\"generation\":{generation},\"helperExitCode\":{},\"helperDeadlineKilled\":{},\"helperElapsedMilliseconds\":{},\"helperStderrCharacters\":{},\"hostThreadId\":{},\"sessionCloseCalled\":true}}",status.code().unwrap_or(-1),killed,started.elapsed().as_millis(),stderr.len(),host_thread))?;
        }
        observer::stop();
        emit(&format!("{{\"event\":\"stopped\",\"ok\":true,\"completedGenerations\":{generation},\"productionObserverStopRequested\":true}}"))?;
        Ok(())
    }
}
fn main() {
    #[cfg(windows)]
    if let Err(error) = desktop::run() {
        eprintln!("DELEGATED_FIXTURE_HOST_FAILED: {error}");
        std::process::exit(1);
    }
    #[cfg(not(windows))]
    {
        eprintln!("WINDOWS_DESKTOP_REQUIRED");
        std::process::exit(1);
    }
}
