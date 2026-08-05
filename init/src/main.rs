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

fn main() {
    println!("tars-init: starting as PID 1");

    mount_fs("proc", "/proc", "proc");
    mount_fs("sysfs", "/sys", "sysfs");
    mount_fs("devtmpfs", "/dev", "devtmpfs");

    let shell = CString::new("/usr/bin/fish").expect("CString::new failed");
    let argv: [*const libc::c_char; 2] = [shell.as_ptr(), ptr::null()];

    unsafe {
        libc::execve(shell.as_ptr(), argv.as_ptr(), environ);
    }

    let errno = unsafe { *libc::__errno_location() };
    eprintln!("tars-init: execve failed (errno {})", errno);
}
