//! Build-time removal of the development-only C# compiler fallback.
//! All production parameter parsing, DLL checks, operations and cleanup remain
//! byte-for-byte slices of the single maintained PowerShell source.
const START: &str = "    $script:NativeBackend = 'source-compiled-cli'";
const END: &str = "    [NativeCancellation]::Configure($NativeCancellationEvent)";
const FAILURE: &str = "        throw 'NATIVE_ASSEMBLY: Packaged launcher requires its native DLL.'";

pub fn generate(source: &str) -> Result<String, &'static str> {
    if source.matches(START).count() != 1 || source.matches(END).count() != 1 {
        return Err("LAUNCHER_BOUNDARY: expected unique fallback and runtime boundaries");
    }
    let newline = if source.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    };
    if source.replace("\r\n", "").contains('\r') {
        return Err("LAUNCHER_NEWLINE: unsupported lone carriage return");
    }
    let start = source.find(START).unwrap();
    let runtime = source.find(END).unwrap();
    if runtime <= start {
        return Err("LAUNCHER_ORDER: invalid fallback order");
    }
    let closing = format!("    }}{newline}");
    let end = runtime
        .checked_sub(closing.len())
        .ok_or("LAUNCHER_CLOSE: missing fallback close")?;
    if &source[end..runtime] != closing
        || !source[..start].ends_with(&format!("    }} else {{{newline}"))
    {
        return Err("LAUNCHER_CLOSE: fallback braces changed");
    }
    let removed = &source[start..end];
    if removed.matches("    $source = @'").count() != 1
        || removed.matches(&format!("{newline}'@{newline}")).count() != 1
        || !removed.ends_with(&format!(
            "    Add-Type -TypeDefinition $source -ReferencedAssemblies $references{newline}"
        ))
    {
        return Err("LAUNCHER_FALLBACK: compiler-only fallback changed");
    }
    Ok(format!(
        "{}{FAILURE}{newline}{}",
        &source[..start],
        &source[end..]
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    const SOURCE: &str = include_str!("native/windows.ps1");
    #[test]
    fn actual_source_keeps_both_entrypoint_slices_exactly() {
        let result = generate(SOURCE).unwrap();
        let start = SOURCE.find(START).unwrap();
        let runtime = SOURCE.find(END).unwrap();
        assert!(result.starts_with(&SOURCE[..start]));
        assert!(result.ends_with(&SOURCE[runtime..]));
        assert!(!result.contains("$source = @'"));
        assert!(!result.contains("Add-Type -TypeDefinition"));
        assert!(result.contains("Packaged launcher requires its native DLL."));
        assert!(result.len() < SOURCE.len() / 3);
        // Removing the single generated throw gives exactly the original two
        // slices, including the closing else brace: no second entrypoint exists.
        let newline_len = if SOURCE.contains("\r\n") { 2 } else { 1 };
        let right = result.find(FAILURE).unwrap() + FAILURE.len() + newline_len;
        assert_eq!(&result[right..], &SOURCE[runtime - 5 - newline_len..]);
    }
    #[test]
    fn crlf_and_bom_are_preserved_without_rewriting_production_code() {
        let lf = SOURCE.replace("\r\n", "\n");
        let expected = generate(&lf).unwrap();
        let crlf = lf.replace('\n', "\r\n");
        assert_eq!(generate(&crlf).unwrap(), expected.replace('\n', "\r\n"));
        assert_eq!(
            generate(&format!("\u{feff}{lf}")).unwrap(),
            format!("\u{feff}{expected}")
        );
    }
    #[test]
    fn ambiguous_missing_or_moved_boundaries_fail_closed() {
        for source in [
            SOURCE.replace(START, ""),
            SOURCE.replace(END, ""),
            format!("{SOURCE}\n{START}"),
            format!("{SOURCE}\n{END}"),
            SOURCE.replace(
                "Add-Type -TypeDefinition $source -ReferencedAssemblies $references",
                "Write-Host changed",
            ),
        ] {
            assert!(generate(&source).is_err());
        }
    }
}
