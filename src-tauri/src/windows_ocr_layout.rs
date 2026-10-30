//! Geometry-only port of Windows helper Join-OcrLayoutLines. Never normalize text.
#[derive(Clone, Debug)]
pub struct Line {
    pub text: String,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}
impl Line {
    pub fn valid(&self) -> bool {
        [self.x, self.y, self.width, self.height]
            .iter()
            .all(|v| v.is_finite())
            && self.width > 0.0
            && self.height > 0.0
    }
}
fn structural(text: &str) -> bool {
    // Match the existing PowerShell/.NET pattern, including Unicode decimal
    // list numbers and .NET word-boundary categories (L, Mn, Nd, Pc).
    static PATTERN: std::sync::LazyLock<regex::Regex> = std::sync::LazyLock::new(|| {
        regex::Regex::new(r"^\s|\t|\||^\s*(?:[-*+•]\s|\d+[.)]\s|#{1,6}\s|>\s|```|~~~|//|/\*|\*/|[{}]|(?:if|for|while|def|class|import|return|const|let|var|function)(?:$|[^\p{L}\p{Mn}\p{Nd}\p{Pc}])|https?://|www\.)")
            .expect("static OCR structural pattern")
    });
    PATTERN.is_match(text)
}
fn overlap(a: &Line, b: &Line) -> f64 {
    ((a.x + a.width).min(b.x + b.width) - a.x.max(b.x)).max(0.0)
}
pub fn join(lines: &[Line], geometry: bool) -> String {
    let mut heights: Vec<_> = lines
        .iter()
        .filter(|l| l.valid())
        .map(|l| l.height)
        .collect();
    if !geometry || heights.is_empty() {
        return lines
            .iter()
            .map(|l| l.text.as_str())
            .collect::<Vec<_>>()
            .join("\n");
    }
    heights.sort_by(f64::total_cmp);
    let m = heights.len() / 2;
    let median = if heights.len() % 2 == 0 {
        (heights[m - 1] + heights[m]) / 2.0
    } else {
        heights[m]
    };
    let mut groups = vec![0; lines.len()];
    let mut pitches = vec![Vec::<f64>::new()];
    let mut group = 0;
    for i in 1..lines.len() {
        let (a, b) = (&lines[i - 1], &lines[i]);
        if a.valid() && b.valid() {
            let same_column = overlap(a, b) > 0.1 * a.width.min(b.width);
            if !same_column && b.y < a.y - 0.9 * median {
                group += 1;
                pitches.push(Vec::new());
            }
            let pitch = b.y - a.y;
            if same_column && pitch > 0.0 && !structural(&a.text) && !structural(&b.text) {
                pitches[group].push(pitch);
            }
        }
        groups[i] = group;
    }
    let baselines: Vec<_> = pitches
        .iter_mut()
        .map(|p| {
            p.sort_by(f64::total_cmp);
            (p.len() >= 2).then(|| p[(p.len() - 1) / 2])
        })
        .collect();
    let mut text = String::new();
    let mut inside_fence = false;
    for (i, b) in lines.iter().enumerate() {
        if i > 0 {
            let a = &lines[i - 1];
            let mut paragraph = false;
            if !inside_fence
                && !structural(&a.text)
                && !structural(&b.text)
                && a.valid()
                && b.valid()
            {
                let height = median.max(a.height.min(b.height));
                let pitch = b.y - a.y;
                let reset = overlap(a, b) <= 0.1 * a.width.min(b.width) && b.y < a.y - 0.9 * height;
                let unusual = baselines[groups[i]].is_some_and(|base| {
                    pitch >= 1.6 * base && pitch - base >= (0.9 * height).max(0.35 * base)
                });
                paragraph = reset || unusual || b.y - (a.y + a.height) >= 3.0 * height;
            }
            text.push_str(if paragraph { "\n\n" } else { "\n" });
        }
        text.push_str(&b.text);
        let trimmed = b.text.trim_start();
        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            inside_fence = !inside_fence;
        }
    }
    text
}
#[cfg(test)]
mod tests {
    use super::*;
    fn line(text: &str, x: f64, y: f64) -> Line {
        Line {
            text: text.into(),
            x,
            y,
            width: 100.0,
            height: 10.0,
        }
    }
    #[test]
    fn ps_paragraph_column_fractional_and_rotation_fixtures() {
        let lines = vec![
            line("first line", 0.0, 0.0),
            line("second line", 0.0, 14.0),
            line("next paragraph", 0.0, 38.0),
            line("continued paragraph", 0.0, 52.0),
            line("column two", 130.0, 0.0),
            line("still column two", 130.0, 14.0),
        ];
        let expected = "first line\nsecond line\n\nnext paragraph\ncontinued paragraph\n\ncolumn two\nstill column two";
        assert_eq!(join(&lines, true), expected);
        let scaled: Vec<_> = lines
            .iter()
            .cloned()
            .map(|mut l| {
                l.x /= 1000.0;
                l.y /= 1000.0;
                l.width /= 1000.0;
                l.height /= 1000.0;
                l
            })
            .collect();
        assert_eq!(join(&scaled, true), expected);
        assert_eq!(
            join(&lines, false),
            lines
                .iter()
                .map(|l| l.text.as_str())
                .collect::<Vec<_>>()
                .join("\n")
        );
    }
    #[test]
    fn ps_wide_leading_sparse_and_invalid_fixtures() {
        let lines = vec![
            line("wide first", 0.0, 0.0),
            line("wide second", 0.0, 24.0),
            line("wide third", 0.0, 48.0),
            line("new paragraph", 0.0, 102.0),
            line("paragraph continued", 0.0, 126.0),
        ];
        assert_eq!(
            join(&lines, true),
            "wide first\nwide second\nwide third\n\nnew paragraph\nparagraph continued"
        );
        assert_eq!(join(&lines[..2], true), "wide first\nwide second");
        assert_eq!(
            join(&[line("unmodified  spaces", f64::NAN, 0.0)], true),
            "unmodified  spaces"
        );
        assert_eq!(join(&[], true), "");
    }
    #[test]
    fn ps_structures_and_fences_remain_verbatim() {
        for texts in [
            [
                "- first item",
                "  indented continuation",
                "    return value;",
            ],
            ["```rust", "arbitrary code", "```"],
            ["~~~", "plain code", "~~~"],
            ["1. item", "2) item", "# title"],
            ["https://example.test", "a|b", "return value"],
        ] {
            let lines: Vec<_> = texts
                .iter()
                .enumerate()
                .map(|(i, t)| line(t, 0.0, i as f64 * 100.0))
                .collect();
            assert_eq!(join(&lines, true), texts.join("\n"));
        }
    }
    #[test]
    fn structural_unicode_matches_powershell_categories() {
        assert!(structural("１. item"));
        assert!(!structural("return\u{301} value"));
        assert!(!structural("Class value"));
        assert!(structural("return(value)"));
    }
    #[test]
    fn ps_subpixel_overlap_and_baseline() {
        let lines: Vec<_> = [0.1, 0.114, 0.138, 0.152]
            .iter()
            .enumerate()
            .map(|(i, y)| Line {
                text: format!("line {i}"),
                x: if i == 0 { 0.11 } else { 0.12 },
                y: *y,
                width: if i == 0 { 0.15 } else { 0.14 },
                height: 0.01,
            })
            .collect();
        assert_eq!(join(&lines, true), "line 0\nline 1\n\nline 2\nline 3");
    }
}
