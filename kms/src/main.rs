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

#[repr(C)]
#[derive(Debug, Default, Clone, Copy)]
struct DrmModeModeinfo {
    clock: u32,
    hdisplay: u16,
    hsync_start: u16,
    hsync_end: u16,
    htotal: u16,
    hskew: u16,
    vdisplay: u16,
    vsync_start: u16,
    vsync_end: u16,
    vtotal: u16,
    vscan: u16,
    vrefresh: u32,
    flags: u32,
    mode_type: u32,
    name: [u8; 32],
}

#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeGetConnector {
    encoders_ptr: u64,
    modes_ptr: u64,
    props_ptr: u64,
    prop_values_ptr: u64,
    count_modes: u32,
    count_props: u32,
    count_encoders: u32,
    encoder_id: u32,
    connector_id: u32,
    connector_type: u32,
    connector_type_id: u32,
    connection: u32,
    mm_width: u32,
    mm_height: u32,
    subpixel: u32,
    pad: u32,
}

#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeGetEncoder {
    encoder_id: u32,
    encoder_type: u32,
    crtc_id: u32,
    possible_crtcs: u32,
    possible_clones: u32,
}

#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeCreateDumb {
    height: u32,
    width: u32,
    bpp: u32,
    flags: u32,
    handle: u32,
    pitch: u32,
    size: u64,
}

#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeMapDumb {
    handle: u32,
    pad: u32,
    offset: u64,
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

fn get_resources(fd: i32) -> io::Result<(Vec<u32>, Vec<u32>, Vec<u32>)> {
    let mut res = DrmModeCardRes::default();
    unsafe { drm_ioctl(fd, drm_iowr(0xA0, size_of::<DrmModeCardRes>()), &mut res)? };

    let mut crtc_ids = vec![0u32; res.count_crtcs as usize];
    let mut connector_ids = vec![0u32; res.count_connectors as usize];
    let mut encoder_ids = vec![0u32; res.count_encoders as usize];

    res.crtc_id_ptr = crtc_ids.as_mut_ptr() as u64;
    res.connector_id_ptr = connector_ids.as_mut_ptr() as u64;
    res.encoder_id_ptr = encoder_ids.as_mut_ptr() as u64;
    res.fb_id_ptr = 0;

    unsafe { drm_ioctl(fd, drm_iowr(0xA0, size_of::<DrmModeCardRes>()), &mut res)? };

    println!(
        "kms: {} crtcs, {} connectors, {} encoders",
        res.count_crtcs, res.count_connectors, res.count_encoders
    );

    Ok((crtc_ids, connector_ids, encoder_ids))
}

fn find_connected_connector(
    fd: i32,
    connector_ids: &[u32],
) -> io::Result<(DrmModeGetConnector, DrmModeModeinfo, Vec<u32>)> {
    for &id in connector_ids {
        let mut conn = DrmModeGetConnector {
            connector_id: id,
            ..Default::default()
        };
        unsafe { drm_ioctl(fd, drm_iowr(0xA7, size_of::<DrmModeGetConnector>()), &mut conn)? };

        if conn.connection != 1 || conn.count_modes == 0 {
            continue;
        }

        let mut modes = vec![DrmModeModeinfo::default(); conn.count_modes as usize];
        let mut encoders = vec![0u32; conn.count_encoders as usize];
        conn.modes_ptr = modes.as_mut_ptr() as u64;
        conn.encoders_ptr = encoders.as_mut_ptr() as u64;
        conn.props_ptr = 0;
        conn.prop_values_ptr = 0;
        conn.count_props = 0;
        unsafe { drm_ioctl(fd, drm_iowr(0xA7, size_of::<DrmModeGetConnector>()), &mut conn)? };

        let mode = modes[0];
        println!(
            "kms: connector {} connected, mode {}x{}",
            id, mode.hdisplay, mode.vdisplay
        );
        return Ok((conn, mode, encoders));
    }

    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "no connected connector with modes found",
    ))
}

fn find_crtc(fd: i32, encoder_id: u32, crtc_ids: &[u32]) -> io::Result<u32> {
    let mut enc = DrmModeGetEncoder {
        encoder_id,
        ..Default::default()
    };
    unsafe { drm_ioctl(fd, drm_iowr(0xA6, size_of::<DrmModeGetEncoder>()), &mut enc)? };

    if enc.crtc_id != 0 {
        return Ok(enc.crtc_id);
    }

    for (i, &crtc_id) in crtc_ids.iter().enumerate() {
        if enc.possible_crtcs & (1 << i) != 0 {
            return Ok(crtc_id);
        }
    }

    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "no usable crtc for encoder",
    ))
}

fn main() -> io::Result<()> {
    ensure_devtmpfs_mounted();

    let file = File::options()
        .read(true)
        .write(true)
        .open("/dev/dri/card0")?;
    let fd = file.as_raw_fd();

    let (crtc_ids, connector_ids, _encoder_ids) = get_resources(fd)?;
    let (connector, mode, encoders) = find_connected_connector(fd, &connector_ids)?;
    let encoder_id = if connector.encoder_id != 0 {
        connector.encoder_id
    } else {
        *encoders
            .first()
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "connector has no encoders"))?
    };
    let crtc_id = find_crtc(fd, encoder_id, &crtc_ids)?;

    println!("kms: selected crtc {}", crtc_id);

    let mut dumb = DrmModeCreateDumb {
        height: mode.vdisplay as u32,
        width: mode.hdisplay as u32,
        bpp: 32,
        ..Default::default()
    };
    unsafe { drm_ioctl(fd, drm_iowr(0xB2, size_of::<DrmModeCreateDumb>()), &mut dumb)? };
    println!(
        "kms: dumb buffer handle={} pitch={} size={}",
        dumb.handle, dumb.pitch, dumb.size
    );

    let mut map = DrmModeMapDumb {
        handle: dumb.handle,
        ..Default::default()
    };
    unsafe { drm_ioctl(fd, drm_iowr(0xB3, size_of::<DrmModeMapDumb>()), &mut map)? };

    let map_ptr = unsafe {
        libc::mmap(
            ptr::null_mut(),
            dumb.size as usize,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_SHARED,
            fd,
            map.offset as libc::off_t,
        )
    };
    if map_ptr == libc::MAP_FAILED {
        return Err(io::Error::last_os_error());
    }

    let red: u32 = 0x00FF_0000;
    for row in 0..dumb.height as usize {
        let row_start = row * dumb.pitch as usize;
        for col in 0..dumb.width as usize {
            let offset = row_start + col * 4;
            unsafe {
                let pixel_ptr = (map_ptr as *mut u8).add(offset) as *mut u32;
                pixel_ptr.write_volatile(red);
            }
        }
    }
    println!("kms: filled framebuffer with solid red");

    Ok(())
}
