use std::ffi::CString;
use std::ptr;

extern "C" {
    static environ: *const *const libc::c_char;
}

fn mount_fs(source: &str, target: &str, fstype: &str) {
    let source_c = CString::new(source).expect("CString::new failed");
    let target_c = CString::new(target).expect("CString::new failed");
    let fstype_c = CString::new(fstype).expect("CString::new failed");

    let ret = unsafe {
        libc::mount(
            source_c.as_ptr(),
            target_c.as_ptr(),
            fstype_c.as_ptr(),
            0,
            ptr::null(),
        )
    };

    if ret == 0 {
        println!("tars-init: mounted {} at {}", fstype, target);
    } else {
        let errno = unsafe { *libc::__errno_location() };
        println!(
            "tars-init: failed to mount {} at {} (errno {})",
            fstype, target, errno
        );
    }
}

fn log_drm_device_presence() {
    if std::path::Path::new("/dev/dri/card0").exists() {
        println!("tars-init: /dev/dri/card0 exists");
    } else {
        println!("tars-init: /dev/dri/card0 not found");
    }
}

fn run_terminal() {
    let pid = unsafe { libc::fork() };
    if pid == 0 {
        let terminal = CString::new("/terminal").expect("CString::new failed");
        let argv: [*const libc::c_char; 2] = [terminal.as_ptr(), ptr::null()];
        unsafe {
            libc::execve(terminal.as_ptr(), argv.as_ptr(), environ);
        }
        let errno = unsafe { *libc::__errno_location() };
        eprintln!("tars-init: execve /terminal failed (errno {})", errno);
        unsafe { libc::_exit(1) };
    } else if pid > 0 {
        println!("tars-init: forked terminal (pid {})", pid);
    } else {
        let errno = unsafe { *libc::__errno_location() };
        println!("tars-init: fork for terminal failed (errno {})", errno);
    }
}

fn setup_controlling_terminal() {
    let console = CString::new("/dev/console").expect("CString::new failed");
    let fd = unsafe { libc::open(console.as_ptr(), libc::O_RDWR) };
    if fd < 0 {
        let errno = unsafe { *libc::__errno_location() };
        println!("tars-init: failed to open /dev/console (errno {})", errno);
        return;
    }

    unsafe {
        libc::setsid();
        libc::ioctl(fd, libc::TIOCSCTTY, 0);
        libc::dup2(fd, 0);
        libc::dup2(fd, 1);
        libc::dup2(fd, 2);
        if fd > 2 {
            libc::close(fd);
        }
    }

    println!("tars-init: set up /dev/console as controlling terminal");
}

fn main() {
    println!("tars-init: starting as PID 1");

    mount_fs("proc", "/proc", "proc");
    mount_fs("sysfs", "/sys", "sysfs");
    mount_fs("devtmpfs", "/dev", "devtmpfs");

    log_drm_device_presence();

    run_terminal();

    setup_controlling_terminal();

    let shell = CString::new("/usr/bin/fish").expect("CString::new failed");
    let argv: [*const libc::c_char; 2] = [shell.as_ptr(), ptr::null()];

    unsafe {
        libc::execve(shell.as_ptr(), argv.as_ptr(), environ);
    }

    let errno = unsafe { *libc::__errno_location() };
    eprintln!("tars-init: execve failed (errno {})", errno);
}
