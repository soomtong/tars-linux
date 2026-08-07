use std::ffi::CString;
use std::fs::File;
use std::io;
use std::mem::size_of;
use std::os::unix::io::AsRawFd;
use std::ptr;

const DRM_IOCTL_BASE: u32 = 'd' as u32;

const fn drm_iowr(nr: u32, size: usize) -> libc::c_ulong {
    ((3u32 << 30) | (DRM_IOCTL_BASE << 8) | nr | ((size as u32) << 16)) as libc::c_ulong
}

#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeCardRes {
    fb_id_ptr: u64,
    crtc_id_ptr: u64,
    connector_id_ptr: u64,
    encoder_id_ptr: u64,
    count_fbs: u32,
    count_crtcs: u32,
    count_connectors: u32,
    count_encoders: u32,
    min_width: u32,
    max_width: u32,
    min_height: u32,
    max_height: u32,
}

unsafe fn drm_ioctl<T>(fd: i32, request: libc::c_ulong, arg: &mut T) -> io::Result<()> {
    let ret = libc::ioctl(fd, request, arg as *mut T as *mut libc::c_void);
    if ret < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn ensure_devtmpfs_mounted() {
    let source = CString::new("devtmpfs").expect("CString::new failed");
    let target = CString::new("/dev").expect("CString::new failed");
    let fstype = CString::new("devtmpfs").expect("CString::new failed");
    unsafe {
        libc::mount(source.as_ptr(), target.as_ptr(), fstype.as_ptr(), 0, ptr::null());
    }
}

fn main() -> io::Result<()> {
    ensure_devtmpfs_mounted();

    let file = File::options()
        .read(true)
        .write(true)
        .open("/dev/dri/card0")?;
    let fd = file.as_raw_fd();

    let mut res = DrmModeCardRes::default();
    unsafe { drm_ioctl(fd, drm_iowr(0xA0, size_of::<DrmModeCardRes>()), &mut res)? };

    println!(
        "kms: {} crtcs, {} connectors, {} encoders",
        res.count_crtcs, res.count_connectors, res.count_encoders
    );

    Ok(())
}
