//! Read-only ISO 9660 disc images. No disc is mounted and nothing is executed.
//!
//! The reader accepts cooked images with 2048-byte sectors (`.iso`, `.img`) and
//! raw images with 2352-byte sectors (`.bin`), either alone or named by a CUE
//! sheet. A raw sector holds 2048 data bytes at offset 16 (MODE1) or 24 (MODE2
//! form 1). The CUE track mode selects the layout, else the sync pattern and the
//! mode byte of the volume descriptor sector do.
//!
//! Joliet names are used when the disc has a Joliet volume; else the ISO 9660
//! names without their `;1` version suffix. Rock Ridge, multi-extent files and
//! HFS (Macintosh) volumes are not read.

mod cue;

#[cfg(test)]
mod tests;

use std::collections::HashSet;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

pub use cue::{Track, parse_cue};

/// The data bytes of one logical sector.
pub const SECTOR: u64 = 2048;
/// The bytes of one raw CD sector.
pub const RAW_SECTOR: u64 = 2352;
/// The sync pattern at the start of each raw data sector.
pub const SYNC: [u8; 12] = [0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0];

const FIRST_DESCRIPTOR: u64 = 16;
const MAX_DESCRIPTORS: u64 = 64;
const MAX_DEPTH: usize = 16;
const MAX_ENTRIES: usize = 100_000;
/// One directory can hold this many bytes of records.
const MAX_DIRECTORY_BYTES: u64 = 16 * 1024 * 1024;

const DIRECTORY_FLAG: u8 = 0x02;
const MULTI_EXTENT_FLAG: u8 = 0x80;

/// The position of the data bytes of each sector in the image file.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Layout {
    /// The bytes of one sector in the file.
    pub sector_size: u64,
    /// The offset of the data bytes inside a sector.
    pub data_offset: u64,
    /// The file offset of sector 0.
    pub start: u64,
}

impl Layout {
    pub const COOKED: Layout = Layout {
        sector_size: SECTOR,
        data_offset: 0,
        start: 0,
    };
    pub const MODE1_RAW: Layout = Layout {
        sector_size: RAW_SECTOR,
        data_offset: 16,
        start: 0,
    };
    pub const MODE2_RAW: Layout = Layout {
        sector_size: RAW_SECTOR,
        data_offset: 24,
        start: 0,
    };
}

/// A file or folder of the disc. `path` uses `/` and has no leading slash.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
    extent: u32,
}

/// An open disc image.
pub struct Disc<R: Read + Seek> {
    reader: R,
    layout: Layout,
    root_extent: u32,
    root_size: u64,
    joliet: bool,
    /// The bytes of the image, so that no read goes past its end.
    length: u64,
}

/// True when `path` names a disc image that `open` can try to read: an `.iso`,
/// `.img` or `.cue` file, or a `.bin` file with a raw ISO 9660 data track.
/// A Macintosh `.bin` file (MacBinary) is not a disc image.
pub fn is_image(path: &Path) -> bool {
    let extension = path.extension().map(|extension| extension.to_string_lossy().to_lowercase());

    match extension.as_deref() {
        Some("iso" | "cue" | "img") => true,
        Some("bin") => File::open(path).is_ok_and(|mut file| {
            let length = file.seek(SeekFrom::End(0)).unwrap_or(0);
            detect(&mut file, length).is_ok()
        }),
        _ => false,
    }
}

/// Opens an image file, or the data track that a CUE sheet names.
pub fn open(path: &Path) -> Result<Disc<File>, String> {
    let is_cue = path.extension().is_some_and(|extension| extension.eq_ignore_ascii_case("cue"));
    let (image, layout) = if is_cue {
        let text = std::fs::read(path).map_err(|_| "Cannot read the CUE sheet.".to_string())?;
        let track = parse_cue(&String::from_utf8_lossy(&text))?;
        let folder = path.parent().unwrap_or(Path::new(""));
        (find_track_file(folder, &track.file)?, Some(track.layout))
    } else {
        (path.to_path_buf(), None)
    };

    let file = File::open(&image).map_err(|_| format!("Cannot open the disc image {}.", display_name(&image)))?;
    Disc::new(file, layout)
}

/// The file that a CUE sheet names. CUE sheets made on Windows can differ in case.
fn find_track_file(folder: &Path, name: &str) -> Result<PathBuf, String> {
    // only the file name: a CUE sheet must not name a file outside its folder
    let name = name.rsplit(['/', '\\']).next().unwrap_or(name);
    let exact = folder.join(name);

    if exact.is_file() {
        return Ok(exact);
    }

    if let Ok(entries) = std::fs::read_dir(folder) {
        for entry in entries.flatten() {
            if entry.file_name().to_string_lossy().eq_ignore_ascii_case(name) && entry.path().is_file() {
                return Ok(entry.path());
            }
        }
    }

    Err(format!("The CUE sheet names {name}, but that file is not beside it."))
}

fn display_name(path: &Path) -> String {
    path.file_name()
        .map_or_else(String::new, |name| name.to_string_lossy().into_owned())
}

fn u32_le(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes([bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]])
}

impl<R: Read + Seek> Disc<R> {
    /// Opens an image. Without a layout, the contents select it.
    pub fn new(mut reader: R, layout: Option<Layout>) -> Result<Self, String> {
        let length = reader
            .seek(SeekFrom::End(0))
            .map_err(|_| "Cannot read the disc image.".to_string())?;
        let layout = match layout {
            Some(layout) => layout,
            None => detect(&mut reader, length)?,
        };
        let mut disc = Disc {
            reader,
            layout,
            root_extent: 0,
            root_size: 0,
            joliet: false,
            length,
        };
        disc.read_descriptors()?;
        Ok(disc)
    }

    pub fn layout(&self) -> Layout {
        self.layout
    }

    pub fn is_joliet(&self) -> bool {
        self.joliet
    }

    /// Reads `count` data bytes from logical sector `sector`.
    fn read_data(&mut self, sector: u64, count: u64) -> Result<Vec<u8>, String> {
        let mut data = Vec::with_capacity(count as usize);
        let mut sector = sector;
        let mut remaining = count;
        let error = || "The disc image ends before the data that its directory names.".to_string();

        while remaining > 0 {
            let offset = self.layout.start + sector * self.layout.sector_size + self.layout.data_offset;
            // cooked sectors are contiguous, so one read takes several of them
            let span = if self.layout.sector_size == SECTOR {
                remaining
            } else {
                remaining.min(SECTOR)
            };

            if offset + span > self.length {
                return Err(error());
            }

            self.reader.seek(SeekFrom::Start(offset)).map_err(|_| error())?;
            let before = data.len();
            data.resize(before + span as usize, 0);
            self.reader.read_exact(&mut data[before..]).map_err(|_| error())?;
            remaining -= span;
            sector += span.div_ceil(SECTOR);
        }

        Ok(data)
    }

    fn read_descriptors(&mut self) -> Result<(), String> {
        let mut primary = None;

        for index in 0..MAX_DESCRIPTORS {
            let Ok(descriptor) = self.read_data(FIRST_DESCRIPTOR + index, SECTOR) else {
                break;
            };

            if &descriptor[1..6] != b"CD001" {
                break;
            }

            let root = (u32_le(&descriptor, 156 + 2), u32_le(&descriptor, 156 + 10) as u64);

            match descriptor[0] {
                1 if primary.is_none() => primary = Some(root),
                // a supplementary volume with a Joliet (UCS-2) escape sequence
                2 if descriptor[88] == 0x25 && descriptor[89] == 0x2f && matches!(descriptor[90], 0x40 | 0x43 | 0x45) => {
                    (self.root_extent, self.root_size) = root;
                    self.joliet = true;
                }
                255 => break,
                _ => {}
            }
        }

        if !self.joliet {
            let Some(root) = primary else {
                return Err("This file is not an ISO 9660 disc image.".into());
            };
            (self.root_extent, self.root_size) = root;
        }

        Ok(())
    }

    /// Every file and folder of the disc, parents before children, in disc order.
    pub fn entries(&mut self) -> Result<Vec<Entry>, String> {
        let mut entries = Vec::new();
        let mut visited = HashSet::new();
        self.list(self.root_extent, self.root_size, "", 0, &mut entries, &mut visited)?;
        Ok(entries)
    }

    fn list(
        &mut self,
        extent: u32,
        size: u64,
        prefix: &str,
        depth: usize,
        entries: &mut Vec<Entry>,
        visited: &mut HashSet<u32>,
    ) -> Result<(), String> {
        if depth > MAX_DEPTH || size > MAX_DIRECTORY_BYTES || !visited.insert(extent) {
            return Err("The disc image has a directory loop or a directory that is too deep.".into());
        }

        let records = self.read_data(extent as u64, size)?;
        let mut folders = Vec::new();
        let mut offset = 0usize;

        while offset < records.len() {
            let length = records[offset] as usize;

            // records do not cross a sector; a zero length pads to the next sector
            if length == 0 {
                offset = (offset / SECTOR as usize + 1) * SECTOR as usize;
                continue;
            }

            if length < 34 || offset + length > records.len() {
                return Err("The disc image has a damaged directory record.".into());
            }

            let record = &records[offset..offset + length];
            offset += length;
            let name_length = record[32] as usize;

            if 33 + name_length > record.len() {
                return Err("The disc image has a damaged directory record.".into());
            }

            let raw_name = &record[33..33 + name_length];

            // the records of this folder and of its parent
            if name_length == 1 && raw_name[0] <= 1 {
                continue;
            }

            let flags = record[25];

            if flags & MULTI_EXTENT_FLAG != 0 {
                return Err("The disc image has a file in several extents, which this reader does not support.".into());
            }

            let name = self.decode_name(raw_name);

            if name.is_empty() || name == "." || name == ".." || name.contains(['/', '\\', '\0']) {
                continue;
            }

            let entry = Entry {
                path: if prefix.is_empty() { name } else { format!("{prefix}/{name}") },
                is_dir: flags & DIRECTORY_FLAG != 0,
                size: u32_le(record, 10) as u64,
                extent: u32_le(record, 2),
            };

            if entries.len() >= MAX_ENTRIES {
                return Err("The disc image has too many files.".into());
            }

            if entry.is_dir {
                folders.push(entry.clone());
            }

            entries.push(entry);
        }

        for folder in folders {
            self.list(folder.extent, folder.size, &folder.path, depth + 1, entries, visited)?;
        }

        Ok(())
    }

    fn decode_name(&self, raw: &[u8]) -> String {
        let name = if self.joliet {
            let units: Vec<u16> = raw.chunks_exact(2).map(|pair| u16::from_be_bytes([pair[0], pair[1]])).collect();
            String::from_utf16_lossy(&units)
        } else {
            String::from_utf8_lossy(raw).into_owned()
        };

        clean_name(&name)
    }

    /// The bytes of a file. A file larger than `max_bytes` is refused.
    pub fn read(&mut self, entry: &Entry, max_bytes: u64) -> Result<Vec<u8>, String> {
        if entry.is_dir {
            return Err(format!("{} is a folder.", entry.path));
        }

        if entry.size > max_bytes {
            return Err(format!("{} exceeds the size limit.", entry.path));
        }

        self.read_data(entry.extent as u64, entry.size)
    }
}

/// The name without its ISO 9660 version suffix, or the final dot of a name without an extension.
fn clean_name(name: &str) -> String {
    let mut name = name;

    if let Some(version) = name.rfind(';')
        && version > 0
        && name[version + 1..].bytes().all(|byte| byte.is_ascii_digit())
    {
        name = &name[..version];
    }

    if name.len() > 1 && name.ends_with('.') {
        name = &name[..name.len() - 1];
    }

    name.to_string()
}

/// The layout of an image without a CUE sheet: a cooked image, or a raw image
/// whose volume descriptor sector starts with the sync pattern.
pub fn detect<R: Read + Seek>(reader: &mut R, length: u64) -> Result<Layout, String> {
    let mut read_at = |offset: u64, count: usize| -> Option<Vec<u8>> {
        if offset + count as u64 > length {
            return None;
        }

        let mut bytes = vec![0; count];
        reader.seek(SeekFrom::Start(offset)).ok()?;
        reader.read_exact(&mut bytes).ok()?;
        Some(bytes)
    };

    if read_at(FIRST_DESCRIPTOR * SECTOR + 1, 5).as_deref() == Some(b"CD001") {
        return Ok(Layout::COOKED);
    }

    if let Some(header) = read_at(FIRST_DESCRIPTOR * RAW_SECTOR, 16)
        && header[..12] == SYNC
    {
        let layout = match header[15] {
            1 => Layout::MODE1_RAW,
            2 => Layout::MODE2_RAW,
            _ => return Err("The disc image has an unknown sector mode.".into()),
        };

        if read_at(FIRST_DESCRIPTOR * RAW_SECTOR + layout.data_offset + 1, 5).as_deref() == Some(b"CD001") {
            return Ok(layout);
        }
    }

    Err("This file is not an ISO 9660 disc image.".into())
}
