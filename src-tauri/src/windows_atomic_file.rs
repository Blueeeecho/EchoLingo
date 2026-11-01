//! One handle-based, same-volume rename. Windows 10 1809+ is the app minimum.
//! MoveFileExW rejects replacement while ordinary shared readers are open;
//! FileRenameInfoEx POSIX semantics retain their old snapshot and publish the
//! new file for future opens. Never delete the destination or retry a failure.
use std::{
    fs::File,
    mem::{offset_of, size_of, MaybeUninit},
    os::windows::{ffi::OsStrExt, io::AsRawHandle},
    path::Path,
};
use windows::Win32::{
    Foundation::HANDLE,
    Storage::FileSystem::{FileRenameInfoEx, SetFileInformationByHandle, FILE_RENAME_INFO},
};

pub fn replace(file: &File, path: &Path) -> Result<(), String> {
    let target = std::path::absolute(path).map_err(|_| "无效本地数据路径")?;
    let name: Vec<u16> = target.as_os_str().encode_wide().collect();
    if name.is_empty() || name.len() > 32767 || name.contains(&0) {
        return Err("无效本地数据路径".into());
    }
    let offset = offset_of!(FILE_RENAME_INFO, FileName);
    // Include a terminating zero in the buffer, but not in FileNameLength.
    let length = (offset + (name.len() + 1) * size_of::<u16>()).max(size_of::<FILE_RENAME_INFO>());
    // Use the SDK binding's actual alignment/layout, including its flexible
    // trailing UTF-16 array, rather than hard-coding x64 structure offsets.
    let mut storage = vec![
        MaybeUninit::<FILE_RENAME_INFO>::zeroed();
        length.div_ceil(size_of::<FILE_RENAME_INFO>())
    ];
    let info = storage.as_mut_ptr().cast::<FILE_RENAME_INFO>();
    // SAFETY: storage is suitably aligned, initialized to zero, and has at
    // least `length` bytes. The pointer and source handle live through the
    // synchronous API call. DELETE access was requested when creating file.
    let result = unsafe {
        std::ptr::write_bytes(
            storage.as_mut_ptr().cast::<u8>(),
            0,
            storage.len() * size_of::<FILE_RENAME_INFO>(),
        );
        (*info).Anonymous.Flags = 0x1 | 0x2; // REPLACE_IF_EXISTS | POSIX_SEMANTICS
        (*info).RootDirectory = HANDLE::default();
        (*info).FileNameLength = (name.len() * size_of::<u16>()) as u32;
        std::ptr::copy_nonoverlapping(
            name.as_ptr(),
            storage.as_mut_ptr().cast::<u8>().add(offset).cast::<u16>(),
            name.len(),
        );
        SetFileInformationByHandle(
            HANDLE(file.as_raw_handle()),
            FileRenameInfoEx,
            info.cast(),
            length as u32,
        )
    };
    result.map_err(|error| {
        format!(
            "无法原子替换本地数据；原文件保留 (Windows HRESULT 0x{:08X})",
            error.code().0 as u32
        )
    })
}
