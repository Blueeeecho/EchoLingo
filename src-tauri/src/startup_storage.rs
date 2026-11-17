//! Fail closed on unreadable data; preserve invalid bytes before allowing a reset.
use std::{
    fs,
    io::{self, Write},
    path::Path,
};

pub fn load<T>(
    path: &Path,
    decode: impl FnOnce(&[u8]) -> Option<T>,
    default: impl FnOnce() -> T,
    label: &str,
    warnings: &mut Vec<String>,
) -> io::Result<T> {
    load_with(
        fs::read(path),
        decode,
        default,
        |bytes| preserve(path, bytes),
        label,
        warnings,
    )
}

fn load_with<T>(
    read: io::Result<Vec<u8>>,
    decode: impl FnOnce(&[u8]) -> Option<T>,
    default: impl FnOnce() -> T,
    preserve_bytes: impl FnOnce(&[u8]) -> io::Result<()>,
    label: &str,
    warnings: &mut Vec<String>,
) -> io::Result<T> {
    let bytes = match read {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(default()),
        Err(error) => {
            return Err(io::Error::new(
                error.kind(),
                format!(
                "{label}无法读取（{:?}）；为保护原文件，未使用默认值覆盖，请检查数据目录权限后重试",
                error.kind()
            ),
            ))
        }
    };
    if let Some(value) = decode(&bytes) {
        return Ok(value);
    }
    preserve_bytes(&bytes).map_err(|error| io::Error::new(error.kind(),
        format!("{label}无法解析，恢复副本保存失败（{:?}）；为保护原文件，已停止加载，请检查数据目录后重试", error.kind())))?;
    warnings.push(format!("{label}无法解析，已逐字节保存 .recovery 副本；本次使用默认值。恢复文件保留在应用数据目录，请勿直接删除"));
    Ok(default())
}

fn preserve(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let mut nonce = [0u8; 16];
    getrandom::fill(&mut nonce).map_err(|_| io::Error::other("无法生成恢复文件名"))?;
    let suffix: String = nonce.iter().map(|byte| format!("{byte:02x}")).collect();
    let mut name = path
        .file_name()
        .ok_or_else(|| io::Error::other("无效数据文件名"))?
        .to_os_string();
    name.push(format!(".{suffix}.recovery"));
    let backup = path.with_file_name(name);
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&backup)?;
    let result = file.write_all(bytes).and_then(|_| file.sync_all());
    drop(file);
    if let Err(error) = result {
        let _ = fs::remove_file(&backup);
        return Err(error);
    }
    // Original is still untouched. Verify the complete copy before reset is permitted.
    if fs::read(&backup)? != bytes {
        return Err(io::Error::other("恢复副本校验失败"));
    }
    #[cfg(unix)]
    {
        // Persist the directory entry before a later settings save can replace
        // the original. If this fails, startup also fails closed.
        fs::File::open(
            path.parent()
                .ok_or_else(|| io::Error::other("无效数据目录"))?,
        )?
        .sync_all()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Fixture(std::path::PathBuf);
    impl Fixture {
        fn new() -> Self {
            let mut nonce = [0u8; 16];
            getrandom::fill(&mut nonce).unwrap();
            let root = std::env::temp_dir().join(format!("echolingo-recovery-{:x?}", nonce));
            fs::create_dir(&root).unwrap();
            Self(root)
        }
        fn path(&self) -> std::path::PathBuf {
            self.0.join("settings.json")
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    fn decode(bytes: &[u8]) -> Option<u32> {
        std::str::from_utf8(bytes).ok()?.parse().ok()
    }
    #[test]
    fn missing_is_not_corruption() {
        let f = Fixture::new();
        let mut warnings = vec![];
        assert_eq!(
            load(&f.path(), decode, || 20, "设置", &mut warnings).unwrap(),
            20
        );
        assert!(warnings.is_empty());
        assert_eq!(fs::read_dir(&f.0).unwrap().count(), 0);
    }
    #[test]
    fn valid_bytes_are_not_rewritten() {
        let f = Fixture::new();
        fs::write(f.path(), b"25").unwrap();
        let mut warnings = vec![];
        assert_eq!(
            load(&f.path(), decode, || 20, "设置", &mut warnings).unwrap(),
            25
        );
        assert!(warnings.is_empty());
        assert_eq!(fs::read_dir(&f.0).unwrap().count(), 1);
    }
    #[test]
    fn invalid_bytes_survive_subsequent_save() {
        let f = Fixture::new();
        let bytes = b"{broken\xff\x00json";
        fs::write(f.path(), bytes).unwrap();
        let mut warnings = vec![];
        assert_eq!(
            load(&f.path(), decode, || 20, "设置", &mut warnings).unwrap(),
            20
        );
        assert_eq!(fs::read(f.path()).unwrap(), bytes);
        fs::write(f.path(), b"20").unwrap();
        let backups: Vec<_> = fs::read_dir(&f.0)
            .unwrap()
            .map(|p| p.unwrap().path())
            .filter(|p| p.extension().is_some_and(|e| e == "recovery"))
            .collect();
        assert_eq!(backups.len(), 1);
        assert_eq!(fs::read(&backups[0]).unwrap(), bytes);
        assert_eq!(warnings.len(), 1);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&backups[0]).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
    }
    #[test]
    fn unreadable_is_not_missing() {
        let f = Fixture::new();
        fs::create_dir(f.path()).unwrap();
        let mut warnings = vec![];
        assert!(load(&f.path(), decode, || 20, "设置", &mut warnings).is_err());
        assert!(f.path().is_dir());
        assert!(warnings.is_empty());
    }
    #[test]
    fn backup_failure_preserves_original() {
        let f = Fixture::new();
        fs::write(f.path(), b"broken").unwrap();
        // A nonexistent backup parent fails without changing the real source.
        assert!(preserve(&f.0.join("missing/settings.json"), b"broken").is_err());
        assert_eq!(fs::read(f.path()).unwrap(), b"broken");
    }
    #[test]
    fn access_denied_never_uses_writable_defaults() {
        let mut warnings = vec![];
        let result = load_with::<u32>(
            Err(io::Error::from(io::ErrorKind::PermissionDenied)),
            decode,
            || panic!("must not default"),
            |_| panic!("must not preserve unread bytes"),
            "设置",
            &mut warnings,
        );
        assert_eq!(result.unwrap_err().kind(), io::ErrorKind::PermissionDenied);
        assert!(warnings.is_empty());
    }
    #[test]
    fn failed_preservation_never_allows_default_save() {
        let mut warnings = vec![];
        let result = load_with::<u32>(
            Ok(b"corrupt".to_vec()),
            decode,
            || panic!("must not default"),
            |bytes| {
                assert_eq!(bytes, b"corrupt");
                Err(io::Error::other("injected write failure"))
            },
            "历史",
            &mut warnings,
        );
        assert!(result.is_err());
        assert!(warnings.is_empty());
    }
}
