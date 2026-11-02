use super::*;

#[repr(C)]
pub(super) struct FoundationLogConfigV1 {
    pub(super) struct_size: u32,
    pub(super) api_version: u32,
    pub(super) log_directory: *const c_char,
    pub(super) log_file_name: *const c_char,
    pub(super) max_file_bytes: u64,
    pub(super) max_files: u32,
    pub(super) queue_capacity: u32,
    pub(super) write_buffer_bytes: u32,
    pub(super) block_when_full: u8,
}

#[repr(C)]
pub(super) struct FoundationLogConfigV2 {
    pub(super) struct_size: u32,
    pub(super) api_version: u32,
    pub(super) log_directory: *const c_char,
    pub(super) log_file_name: *const c_char,
    pub(super) max_file_bytes: u64,
    pub(super) max_files: u32,
    pub(super) queue_capacity: u32,
    pub(super) write_buffer_bytes: u32,
    pub(super) block_when_full: u8,
    pub(super) mode: u32,
    pub(super) mmap_spool_path: *const c_char,
    pub(super) mmap_capacity_bytes: u64,
    pub(super) mmap_slot_bytes: u32,
}

#[repr(C)]
pub(super) struct FoundationLogConfigV3 {
    pub(super) struct_size: u32,
    pub(super) api_version: u32,
    pub(super) log_directory: *const c_char,
    pub(super) log_file_name: *const c_char,
    pub(super) max_file_bytes: u64,
    pub(super) max_files: u32,
    pub(super) queue_capacity: u32,
    pub(super) write_buffer_bytes: u32,
    pub(super) block_when_full: u8,
    pub(super) mode: u32,
    pub(super) mmap_spool_path: *const c_char,
    pub(super) mmap_capacity_bytes: u64,
    pub(super) mmap_slot_bytes: u32,
    pub(super) mmap_lanes: u32,
    pub(super) extension_version: u32,
}

#[repr(C)]
pub(super) struct FoundationLogConfigV4 {
    pub(super) struct_size: u32,
    pub(super) api_version: u32,
    pub(super) log_directory: *const c_char,
    pub(super) log_file_name: *const c_char,
    pub(super) max_file_bytes: u64,
    pub(super) max_files: u32,
    pub(super) queue_capacity: u32,
    pub(super) write_buffer_bytes: u32,
    pub(super) block_when_full: u8,
    pub(super) mode: u32,
    pub(super) mmap_spool_path: *const c_char,
    pub(super) mmap_capacity_bytes: u64,
    pub(super) mmap_slot_bytes: u32,
    pub(super) mmap_lanes: u32,
    pub(super) extension_version: u32,
    pub(super) mmap_spsc_lanes: u32,
    pub(super) extension_version_v4: u32,
}

#[repr(C)]
pub(super) struct FoundationLogConfigV5 {
    pub(super) struct_size: u32,
    pub(super) api_version: u32,
    pub(super) log_directory: *const c_char,
    pub(super) log_file_name: *const c_char,
    pub(super) max_file_bytes: u64,
    pub(super) max_files: u32,
    pub(super) queue_capacity: u32,
    pub(super) write_buffer_bytes: u32,
    pub(super) block_when_full: u8,
    pub(super) mode: u32,
    pub(super) mmap_spool_path: *const c_char,
    pub(super) mmap_capacity_bytes: u64,
    pub(super) mmap_slot_bytes: u32,
    pub(super) mmap_lanes: u32,
    pub(super) extension_version: u32,
    pub(super) mmap_spsc_lanes: u32,
    pub(super) extension_version_v4: u32,
    pub(super) output_mode: u32,
    pub(super) io_uring_entries: u32,
    pub(super) extension_version_v5: u32,
}

#[repr(C)]
pub(super) struct FoundationLogConfigV6 {
    pub(super) struct_size: u32,
    pub(super) api_version: u32,
    pub(super) log_directory: *const c_char,
    pub(super) log_file_name: *const c_char,
    pub(super) max_file_bytes: u64,
    pub(super) max_files: u32,
    pub(super) queue_capacity: u32,
    pub(super) write_buffer_bytes: u32,
    pub(super) block_when_full: u8,
    pub(super) mode: u32,
    pub(super) mmap_spool_path: *const c_char,
    pub(super) mmap_capacity_bytes: u64,
    pub(super) mmap_slot_bytes: u32,
    pub(super) mmap_lanes: u32,
    pub(super) extension_version: u32,
    pub(super) mmap_spsc_lanes: u32,
    pub(super) extension_version_v4: u32,
    pub(super) output_mode: u32,
    pub(super) io_uring_entries: u32,
    pub(super) extension_version_v5: u32,
    pub(super) queue_capacity_bytes: u64,
    pub(super) extension_version_v6: u32,
    pub(super) reserved_v6: u32,
}

/// Reads the retained version-1 config prefixes and rejects retired options.
pub(super) unsafe fn parse(config: *const FoundationLogConfig) -> crate::Result<Settings> {
    let struct_size = std::ptr::read_unaligned(config.cast::<u32>()) as usize;
    if struct_size < std::mem::size_of::<FoundationLogConfigV1>() {
        return Err(invalid("config struct_size is too small"));
    }
    let v1 = &*config.cast::<FoundationLogConfigV1>();
    if v1.api_version != 1 {
        return Err(invalid("unsupported logging API version"));
    }
    let mut settings = Settings::new(
        required_path(v1.log_directory, "log_directory")?,
        required_string(v1.log_file_name, "log_file_name")?,
    );
    settings.max_file_bytes = v1.max_file_bytes;
    settings.max_files = v1.max_files as usize;
    settings.queue_capacity = v1.queue_capacity as usize;
    settings.write_buffer_bytes = v1.write_buffer_bytes as usize;
    settings.block_when_full = v1.block_when_full != 0;
    let mut extension_version = 0;
    let mut extension_version_v4 = 0;
    let mut extension_version_v5 = 0;
    if struct_size >= std::mem::size_of::<FoundationLogConfigV3>() {
        let v3 = &*config.cast::<FoundationLogConfigV3>();
        extension_version = v3.extension_version;
        if extension_version >= 3 && v3.mmap_lanes > 1 {
            return Err(invalid(
                "mmap lane modes have been removed; use single mmap",
            ));
        }
    }
    if struct_size >= std::mem::size_of::<FoundationLogConfigV4>() {
        let v4 = &*config.cast::<FoundationLogConfigV4>();
        extension_version_v4 = v4.extension_version_v4;
        if extension_version >= 4 && extension_version_v4 >= 4 && v4.mmap_spsc_lanes != 0 {
            return Err(invalid("mmap SPSC mode has been removed; use single mmap"));
        }
    }
    if struct_size >= std::mem::size_of::<FoundationLogConfigV5>() {
        let v5 = &*config.cast::<FoundationLogConfigV5>();
        extension_version_v5 = v5.extension_version_v5;
        if extension_version >= 5
            && extension_version_v4 >= 4
            && extension_version_v5 >= 5
            && v5.output_mode != 0
        {
            return Err(invalid(
                "optional output modes have been removed; use buffered output",
            ));
        }
    }
    if struct_size >= std::mem::size_of::<FoundationLogConfigV6>()
        && extension_version >= 6
        && extension_version_v4 >= 4
        && extension_version_v5 >= 5
        && (*config.cast::<FoundationLogConfigV6>()).extension_version_v6 >= 6
    {
        let v6 = &*config.cast::<FoundationLogConfigV6>();
        settings.queue_capacity_bytes = usize::try_from(v6.queue_capacity_bytes)
            .map_err(|_| invalid("queue_capacity_bytes does not fit usize"))?;
    }
    if struct_size >= std::mem::size_of::<FoundationLogConfig>()
        && extension_version >= 7
        && extension_version_v4 >= 4
        && extension_version_v5 >= 5
        && (*config).extension_version_v6 >= 6
        && (*config).extension_version_v7 >= 7
    {
        settings.critical_reserve_records = (*config).critical_reserve_records as usize;
        settings.critical_reserve_bytes = usize::try_from((*config).critical_reserve_bytes)
            .map_err(|_| invalid("critical_reserve_bytes does not fit usize"))?;
    }
    if struct_size >= std::mem::size_of::<FoundationLogConfigV2>() {
        let v2 = &*config.cast::<FoundationLogConfigV2>();
        settings.mode = match v2.mode {
            FOUNDATION_LOG_MODE_MEMORY => crate::BackendMode::Memory,
            FOUNDATION_LOG_MODE_MMAP => crate::BackendMode::Mmap {
                spool_path: required_path(v2.mmap_spool_path, "mmap_spool_path")?,
                capacity_bytes: usize::try_from(v2.mmap_capacity_bytes)
                    .map_err(|_| invalid("mmap_capacity_bytes does not fit usize"))?,
                slot_bytes: v2.mmap_slot_bytes as usize,
            },
            _ => return Err(invalid("unsupported backend mode")),
        };
    }
    Ok(settings)
}

fn invalid(message: &str) -> Error {
    Error::InvalidInput(message.to_owned())
}
