//! CUE sheets: the file and sector layout of the first data track.

use super::Layout;

/// The data track that a CUE sheet names.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Track {
    pub file: String,
    pub layout: Layout,
}

/// The first data track of a CUE sheet. Audio tracks are ignored.
pub fn parse_cue(text: &str) -> Result<Track, String> {
    let mut file: Option<String> = None;

    for line in text.lines() {
        let line = line.trim();
        let mut words = line.split_whitespace();

        match words.next().map(str::to_ascii_uppercase).as_deref() {
            Some("FILE") => file = Some(file_name(line[4..].trim())),
            Some("TRACK") => {
                let mode = words.nth(1).unwrap_or("").to_ascii_uppercase();
                let layout = match mode.as_str() {
                    "MODE1/2048" | "MODE2/2048" => Layout::COOKED,
                    "MODE1/2352" => Layout::MODE1_RAW,
                    "MODE2/2352" => Layout::MODE2_RAW,
                    _ => continue,
                };
                let Some(file) = file.clone() else {
                    return Err("The CUE sheet names a track before its file.".into());
                };

                return Ok(Track { file, layout });
            }
            _ => {}
        }
    }

    Err("The CUE sheet has no MODE1 or MODE2 data track.".into())
}

/// The quoted or unquoted file name of a FILE line, without its file type.
fn file_name(rest: &str) -> String {
    if let Some(quoted) = rest.strip_prefix('"') {
        return quoted.split('"').next().unwrap_or("").to_string();
    }

    // FILE name.bin BINARY: the type is the last word
    match rest.rsplit_once(char::is_whitespace) {
        Some((name, _)) => name.trim().to_string(),
        None => rest.to_string(),
    }
}
