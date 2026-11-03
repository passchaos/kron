use super::config::*;
use super::*;
use std::ffi::CString;
use std::fs;

#[test]
fn phase1_config_prefix_remains_abi_compatible() {
    let directory =
        std::env::temp_dir().join(format!("foundation-log-ffi-v1-{}", std::process::id()));
    let _ = fs::remove_dir_all(&directory);
    fs::create_dir_all(&directory).unwrap();
    let directory_string = CString::new(directory.to_str().unwrap()).unwrap();
    let file_name = CString::new("v1.log").unwrap();
    let config = FoundationLogConfigV1 {
        struct_size: std::mem::size_of::<FoundationLogConfigV1>() as u32,
        api_version: 1,
        log_directory: directory_string.as_ptr(),
        log_file_name: file_name.as_ptr(),
        max_file_bytes: 1024,
        max_files: 2,
        queue_capacity: 8,
        write_buffer_bytes: 256,
        block_when_full: 1,
    };
    let mut handle = std::ptr::null_mut();
    let status = unsafe {
        foundation_log_open(
            (&config as *const FoundationLogConfigV1).cast(),
            &mut handle,
        )
    };
    assert_eq!(status, FOUNDATION_LOG_OK);
    assert_eq!(
        unsafe { foundation_log_submit(handle, b"v1 record\n".as_ptr().cast(), 10) },
        FOUNDATION_LOG_OK
    );
    assert_eq!(
        unsafe { foundation_log_flush(handle, 0) },
        FOUNDATION_LOG_OK
    );
    unsafe { foundation_log_close(handle) };
    assert_eq!(fs::read(directory.join("v1.log")).unwrap(), b"v1 record\n");
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn phase2_mmap_config_prefix_remains_abi_compatible() {
    assert!(
        std::mem::size_of::<FoundationLogConfigV2>() < std::mem::size_of::<FoundationLogConfig>()
    );
    let directory =
        std::env::temp_dir().join(format!("foundation-log-ffi-v2-{}", std::process::id()));
    let _ = fs::remove_dir_all(&directory);
    fs::create_dir_all(&directory).unwrap();
    let directory_string = CString::new(directory.to_str().unwrap()).unwrap();
    let file_name = CString::new("v2.log").unwrap();
    let spool_path = CString::new(directory.join("v2.spool").to_str().unwrap()).unwrap();
    let config = FoundationLogConfigV2 {
        struct_size: std::mem::size_of::<FoundationLogConfigV2>() as u32,
        api_version: 1,
        log_directory: directory_string.as_ptr(),
        log_file_name: file_name.as_ptr(),
        max_file_bytes: 1024,
        max_files: 2,
        queue_capacity: 8,
        write_buffer_bytes: 256,
        block_when_full: 1,
        mode: FOUNDATION_LOG_MODE_MMAP,
        mmap_spool_path: spool_path.as_ptr(),
        mmap_capacity_bytes: 4096 + 8 * 512,
        mmap_slot_bytes: 512,
    };
    let mut handle = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            foundation_log_open(
                (&config as *const FoundationLogConfigV2).cast(),
                &mut handle,
            )
        },
        FOUNDATION_LOG_OK
    );
    assert_eq!(
        unsafe { foundation_log_submit(handle, b"v2 record\n".as_ptr().cast(), 10) },
        FOUNDATION_LOG_OK
    );
    assert_eq!(
        unsafe { foundation_log_flush(handle, 0) },
        FOUNDATION_LOG_OK
    );
    unsafe { foundation_log_close(handle) };
    assert_eq!(fs::read(directory.join("v2.log")).unwrap(), b"v2 record\n");
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn retired_lane_config_is_rejected() {
    assert!(
        std::mem::size_of::<FoundationLogConfigV3>() < std::mem::size_of::<FoundationLogConfig>()
    );
    let directory =
        std::env::temp_dir().join(format!("foundation-log-ffi-v3-{}", std::process::id()));
    let _ = fs::remove_dir_all(&directory);
    fs::create_dir_all(&directory).unwrap();
    let directory_string = CString::new(directory.to_str().unwrap()).unwrap();
    let file_name = CString::new("v3.log").unwrap();
    let spool_path = CString::new(directory.join("v3.spool").to_str().unwrap()).unwrap();
    let config = FoundationLogConfigV3 {
        struct_size: std::mem::size_of::<FoundationLogConfigV3>() as u32,
        api_version: 1,
        log_directory: directory_string.as_ptr(),
        log_file_name: file_name.as_ptr(),
        max_file_bytes: 1024,
        max_files: 2,
        queue_capacity: 8,
        write_buffer_bytes: 256,
        block_when_full: 1,
        mode: FOUNDATION_LOG_MODE_MMAP,
        mmap_spool_path: spool_path.as_ptr(),
        mmap_capacity_bytes: 2 * (4096 + 8 * 512),
        mmap_slot_bytes: 512,
        mmap_lanes: 2,
        extension_version: 3,
    };
    let mut handle = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            foundation_log_open(
                (&config as *const FoundationLogConfigV3).cast(),
                &mut handle,
            )
        },
        FOUNDATION_LOG_INVALID_ARGUMENT
    );
    assert!(handle.is_null());
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn retired_spsc_config_is_rejected() {
    assert!(
        std::mem::size_of::<FoundationLogConfigV4>() < std::mem::size_of::<FoundationLogConfig>()
    );
    let directory =
        std::env::temp_dir().join(format!("foundation-log-ffi-v4-{}", std::process::id()));
    let _ = fs::remove_dir_all(&directory);
    fs::create_dir_all(&directory).unwrap();
    let directory_string = CString::new(directory.to_str().unwrap()).unwrap();
    let file_name = CString::new("v4.log").unwrap();
    let spool_path = CString::new(directory.join("v4.spool").to_str().unwrap()).unwrap();
    let config = FoundationLogConfigV4 {
        struct_size: std::mem::size_of::<FoundationLogConfigV4>() as u32,
        api_version: 1,
        log_directory: directory_string.as_ptr(),
        log_file_name: file_name.as_ptr(),
        max_file_bytes: 1024,
        max_files: 2,
        queue_capacity: 8,
        write_buffer_bytes: 256,
        block_when_full: 1,
        mode: FOUNDATION_LOG_MODE_MMAP,
        mmap_spool_path: spool_path.as_ptr(),
        mmap_capacity_bytes: 4096 + 8 * 512,
        mmap_slot_bytes: 512,
        mmap_lanes: 1,
        extension_version: 4,
        mmap_spsc_lanes: 1,
        extension_version_v4: 4,
    };
    let mut handle = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            foundation_log_open(
                (&config as *const FoundationLogConfigV4).cast(),
                &mut handle,
            )
        },
        FOUNDATION_LOG_INVALID_ARGUMENT
    );
    assert!(handle.is_null());
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn phase5_output_config_prefix_remains_abi_compatible() {
    assert!(
        std::mem::size_of::<FoundationLogConfigV5>() < std::mem::size_of::<FoundationLogConfig>()
    );
    let directory =
        std::env::temp_dir().join(format!("foundation-log-ffi-v5-{}", std::process::id()));
    let _ = fs::remove_dir_all(&directory);
    fs::create_dir_all(&directory).unwrap();
    let directory_string = CString::new(directory.to_str().unwrap()).unwrap();
    let file_name = CString::new("v5.log").unwrap();
    let mut config = FoundationLogConfigV5 {
        struct_size: std::mem::size_of::<FoundationLogConfigV5>() as u32,
        api_version: 1,
        log_directory: directory_string.as_ptr(),
        log_file_name: file_name.as_ptr(),
        max_file_bytes: 1024,
        max_files: 2,
        queue_capacity: 8,
        write_buffer_bytes: 256,
        block_when_full: 1,
        mode: FOUNDATION_LOG_MODE_MEMORY,
        mmap_spool_path: std::ptr::null(),
        mmap_capacity_bytes: 0,
        mmap_slot_bytes: 0,
        mmap_lanes: 1,
        extension_version: 5,
        mmap_spsc_lanes: 0,
        extension_version_v4: 4,
        output_mode: 0,
        io_uring_entries: 8,
        extension_version_v5: 5,
    };
    let mut handle = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            foundation_log_open(
                (&config as *const FoundationLogConfigV5).cast(),
                &mut handle,
            )
        },
        FOUNDATION_LOG_OK
    );
    assert_eq!(
        unsafe { foundation_log_submit(handle, b"v5 record\n".as_ptr().cast(), 10) },
        FOUNDATION_LOG_OK
    );
    assert_eq!(
        unsafe { foundation_log_flush(handle, 0) },
        FOUNDATION_LOG_OK
    );
    unsafe { foundation_log_close(handle) };
    assert_eq!(fs::read(directory.join("v5.log")).unwrap(), b"v5 record\n");
    config.output_mode = 1; // Removed legacy io_uring selector.
    assert_eq!(
        unsafe {
            foundation_log_open(
                (&config as *const FoundationLogConfigV5).cast(),
                &mut handle,
            )
        },
        FOUNDATION_LOG_INVALID_ARGUMENT
    );
    assert!(handle.is_null());
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn phase6_queue_byte_capacity_is_applied() {
    let directory =
        std::env::temp_dir().join(format!("foundation-log-ffi-v6-{}", std::process::id()));
    let _ = fs::remove_dir_all(&directory);
    fs::create_dir_all(&directory).unwrap();
    let directory_string = CString::new(directory.to_str().unwrap()).unwrap();
    let file_name = CString::new("v6.log").unwrap();
    let config = FoundationLogConfig {
        struct_size: std::mem::size_of::<FoundationLogConfig>() as u32,
        api_version: 1,
        log_directory: directory_string.as_ptr(),
        log_file_name: file_name.as_ptr(),
        max_file_bytes: 1024,
        max_files: 2,
        queue_capacity: 8,
        write_buffer_bytes: 256,
        block_when_full: 0,
        mode: FOUNDATION_LOG_MODE_MEMORY,
        mmap_spool_path: std::ptr::null(),
        mmap_capacity_bytes: 0,
        mmap_slot_bytes: 0,
        reserved_mmap_lanes: 1,
        extension_version: 6,
        reserved_mmap_spsc_lanes: 0,
        extension_version_v4: 4,
        reserved_output_mode: 0,
        reserved_io_uring_entries: 8,
        extension_version_v5: 5,
        queue_capacity_bytes: 4,
        extension_version_v6: 6,
        reserved_v6: 0,
        critical_reserve_records: 0,
        extension_version_v7: 0,
        critical_reserve_bytes: 0,
    };
    let mut handle = std::ptr::null_mut();
    assert_eq!(
        unsafe { foundation_log_open(&config, &mut handle) },
        FOUNDATION_LOG_OK
    );
    assert_eq!(
        unsafe { foundation_log_submit(handle, b"12345".as_ptr().cast(), 5) },
        FOUNDATION_LOG_RECORD_TOO_LARGE
    );
    assert_eq!(
        unsafe { foundation_log_submit(handle, b"1234".as_ptr().cast(), 4) },
        FOUNDATION_LOG_OK
    );
    assert_eq!(
        unsafe { foundation_log_flush(handle, 0) },
        FOUNDATION_LOG_OK
    );
    unsafe { foundation_log_close(handle) };
    assert_eq!(fs::read(directory.join("v6.log")).unwrap(), b"1234");
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn phase7_critical_reserve_is_applied() {
    let directory = CString::new("/tmp").unwrap();
    let file_name = CString::new("priority.log").unwrap();
    let config = FoundationLogConfig {
        struct_size: std::mem::size_of::<FoundationLogConfig>() as u32,
        api_version: 1,
        log_directory: directory.as_ptr(),
        log_file_name: file_name.as_ptr(),
        max_file_bytes: 1024,
        max_files: 2,
        queue_capacity: 1024,
        write_buffer_bytes: 256,
        block_when_full: 0,
        mode: FOUNDATION_LOG_MODE_MEMORY,
        mmap_spool_path: std::ptr::null(),
        mmap_capacity_bytes: 0,
        mmap_slot_bytes: 0,
        reserved_mmap_lanes: 0,
        extension_version: 7,
        reserved_mmap_spsc_lanes: 0,
        extension_version_v4: 4,
        reserved_output_mode: 0,
        reserved_io_uring_entries: 0,
        extension_version_v5: 5,
        queue_capacity_bytes: 1024 * 1024,
        extension_version_v6: 6,
        reserved_v6: 0,
        critical_reserve_records: 17,
        extension_version_v7: 7,
        critical_reserve_bytes: 64 * 1024,
    };
    let settings = unsafe { config::parse(&config) }.unwrap();
    assert_eq!(settings.critical_reserve_records, 17);
    assert_eq!(settings.critical_reserve_bytes, 64 * 1024);
}
