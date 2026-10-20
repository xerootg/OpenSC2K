//! Copy the files of a disc image or a ZIP archive to a folder, so the importer
//! can read a game disc that the system cannot mount (for example on Android).
//!
//! Disc images: ISO 9660 `.iso`/`.img`, and raw `.bin` with or without a `.cue`
//! sheet; see `sc2k_formats::disc`. Archives: ZIP. Each name is checked, so no
//! file is written outside the destination folder.

use sc2k_formats::{disc, zip};
use std::fs;
use std::path::{Component, Path, PathBuf};

/// A file larger than this is skipped. The import scan does not read larger files.
pub const MAX_FILE_BYTES: u64 = 64 * 1024 * 1024;
/// The unpacked files of one source can use this many bytes.
pub const MAX_TOTAL_BYTES: u64 = 1024 * 1024 * 1024;
/// A ZIP archive is read into memory, so it has a lower limit.
const MAX_ARCHIVE_BYTES: u64 = 512 * 1024 * 1024;

/// The result of an unpack.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Unpacked {
    /// The number of files written.
    pub files: usize,
    /// The names of files that were not written, with the reason.
    pub skipped: Vec<String>,
}

/// The kind of packed source at `path`, or `None` for a folder or another file.
pub fn kind(path: &Path) -> Option<&'static str> {
    if !path.is_file() {
        return None;
    }

    if disc::is_image(path) {
        return Some("disc");
    }

    let extension = path.extension().map(|extension| extension.to_string_lossy().to_lowercase());

    (extension.as_deref() == Some("zip")).then_some("zip")
}

/// Writes the files of the disc image or ZIP archive at `source` below
/// `destination`, which must not exist yet.
pub fn unpack(source: &Path, destination: &Path) -> Result<Unpacked, String> {
    let kind = kind(source).ok_or_else(|| "Select a disc image (.iso, .bin, .cue) or a ZIP archive.".to_string())?;

    if destination.exists() {
        return Err("The unpack folder already exists.".into());
    }

    fs::create_dir_all(destination).map_err(|_| "Cannot create the unpack folder.".to_string())?;

    let result = if kind == "disc" {
        unpack_disc(source, destination)
    } else {
        unpack_zip(source, destination)
    };

    if result.is_err() {
        let _ = fs::remove_dir_all(destination);
    }

    result
}

fn unpack_disc(source: &Path, destination: &Path) -> Result<Unpacked, String> {
    let mut image = disc::open(source)?;
    let mut unpacked = Unpacked::default();
    let mut total = 0u64;

    for entry in image.entries()? {
        let target = safe_join(destination, &entry.path)?;

        if entry.is_dir {
            fs::create_dir_all(&target).map_err(|_| format!("Cannot create the folder {}.", entry.path))?;
            continue;
        }

        if entry.size > MAX_FILE_BYTES || total + entry.size > MAX_TOTAL_BYTES {
            unpacked.skipped.push(format!("{} (too large)", entry.path));
            continue;
        }

        let bytes = image.read(&entry, MAX_FILE_BYTES)?;
        total += bytes.len() as u64;
        write(&target, &bytes, &entry.path)?;
        unpacked.files += 1;
    }

    Ok(unpacked)
}

fn unpack_zip(source: &Path, destination: &Path) -> Result<Unpacked, String> {
    let length = fs::metadata(source).map_or(0, |metadata| metadata.len());

    if length > MAX_ARCHIVE_BYTES {
        return Err("The ZIP archive exceeds the import size limit. Extract it first, then select its folder.".into());
    }

    let bytes = fs::read(source).map_err(|_| "Cannot read the ZIP archive.".to_string())?;
    let archive = zip::decode(&bytes, MAX_FILE_BYTES as i64, MAX_TOTAL_BYTES as i64)?;
    let mut unpacked = Unpacked::default();

    for (name, data) in &archive.members {
        // a folder member has a final slash and no data
        if name.ends_with('/') {
            fs::create_dir_all(safe_join(destination, name.trim_end_matches('/'))?)
                .map_err(|_| format!("Cannot create the folder {name}."))?;
            continue;
        }

        write(&safe_join(destination, name)?, data, name)?;
        unpacked.files += 1;
    }

    Ok(unpacked)
}

/// `relative` below `root`. Absolute paths and parent components are refused.
fn safe_join(root: &Path, relative: &str) -> Result<PathBuf, String> {
    let relative = Path::new(relative);
    let safe = !relative.as_os_str().is_empty() && relative.components().all(|part| matches!(part, Component::Normal(_)));

    if !safe {
        return Err(format!("The source has an unsafe file name: {}", relative.display()));
    }

    Ok(root.join(relative))
}

fn write(target: &Path, bytes: &[u8], name: &str) -> Result<(), String> {
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(|_| format!("Cannot create the folder of {name}."))?;
    }

    // two names that differ only in case on a file system that ignores case keep the first
    if target.exists() {
        return Ok(());
    }

    fs::write(target, bytes).map_err(|_| format!("Cannot write {name}."))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temporary(name: &str) -> PathBuf {
        let folder = std::env::temp_dir().join(format!("sc2k-unpack-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&folder);
        fs::create_dir_all(&folder).unwrap();
        folder
    }

    #[test]
    fn a_zip_archive_unpacks_below_its_folder() {
        let folder = temporary("zip");
        let archive = zip::encode(
            &[
                ("SC2K/DATA/TEXT.DAT".into(), b"abc".as_slice()),
                ("SC2K/README.TXT".into(), b"x".as_slice()),
            ],
            1024,
            4096,
            false,
        )
        .unwrap();
        fs::write(folder.join("game.zip"), archive).unwrap();
        assert_eq!(kind(&folder.join("game.zip")), Some("zip"));

        let unpacked = unpack(&folder.join("game.zip"), &folder.join("out")).unwrap();
        assert_eq!(unpacked.files, 2);
        assert_eq!(fs::read(folder.join("out/SC2K/DATA/TEXT.DAT")).unwrap(), b"abc");
        // the destination must be new
        assert!(unpack(&folder.join("game.zip"), &folder.join("out")).is_err());
        fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn other_files_are_not_packed_sources() {
        let folder = temporary("kind");
        fs::write(folder.join("SimCity.bin"), b"\0\x0bMacBinary").unwrap();
        fs::write(folder.join("broken.iso"), b"\0").unwrap();
        assert_eq!(kind(&folder.join("SimCity.bin")), None);
        assert_eq!(kind(&folder), None);
        // an .iso name is a disc image; its contents are checked by the unpack
        assert_eq!(kind(&folder.join("broken.iso")), Some("disc"));
        assert!(unpack(&folder.join("broken.iso"), &folder.join("out")).is_err());
        assert!(!folder.join("out").exists());
        fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn unsafe_names_are_refused() {
        let root = Path::new("/tmp/root");
        assert!(safe_join(root, "../x").is_err());
        assert!(safe_join(root, "/etc/x").is_err());
        assert!(safe_join(root, "").is_err());
        assert_eq!(safe_join(root, "A/B.DAT").unwrap(), root.join("A/B.DAT"));
    }
}
