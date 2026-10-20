use super::*;
use std::io::Cursor;

const S: usize = SECTOR as usize;

fn record(name: &[u8], extent: u32, size: u32, directory: bool) -> Vec<u8> {
    let mut record = vec![0u8; 33];
    record.extend_from_slice(name);

    if record.len() % 2 == 1 {
        record.push(0);
    }

    record[0] = record.len() as u8;
    record[2..6].copy_from_slice(&extent.to_le_bytes());
    record[6..10].copy_from_slice(&extent.to_be_bytes());
    record[10..14].copy_from_slice(&size.to_le_bytes());
    record[14..18].copy_from_slice(&size.to_be_bytes());
    record[25] = if directory { DIRECTORY_FLAG } else { 0 };
    record[32] = name.len() as u8;
    record
}

fn directory(own: u32, parent: u32, children: &[Vec<u8>]) -> Vec<u8> {
    let mut sector = record(&[0], own, S as u32, true);
    sector.extend(record(&[1], parent, S as u32, true));

    for child in children {
        sector.extend_from_slice(child);
    }

    sector.resize(S, 0);
    sector
}

fn descriptor(kind: u8, root_extent: u32, joliet: bool) -> Vec<u8> {
    let mut sector = vec![0u8; S];
    sector[0] = kind;
    sector[1..6].copy_from_slice(b"CD001");
    sector[6] = 1;

    if joliet {
        sector[88..91].copy_from_slice(&[0x25, 0x2f, 0x45]);
    }

    if kind != 255 {
        sector[156..190].copy_from_slice(&record(&[0], root_extent, S as u32, true));
    }

    sector
}

fn ucs2(text: &str) -> Vec<u8> {
    text.encode_utf16().flat_map(u16::to_be_bytes).collect()
}

/// A cooked image: /README.TXT and /DOS/SC2000.DAT, with an optional Joliet tree
/// that spells the names in mixed case.
fn cooked_image(joliet: bool) -> Vec<u8> {
    let mut image = vec![0u8; 16 * S];
    image.extend(descriptor(1, 19, false));
    image.extend(if joliet { descriptor(2, 22, true) } else { descriptor(0, 0, false) });
    image.extend(descriptor(255, 0, false));
    // 19: root, 20: DOS, 21: data. 22 and 23: the Joliet root and DOS folders
    image.extend(directory(
        19,
        19,
        &[record(b"DOS", 20, S as u32, true), record(b"README.TXT;1", 21, 5, false)],
    ));
    image.extend(directory(20, 19, &[record(b"SC2000.DAT;1", 21, 3, false)]));
    let mut data = b"hello".to_vec();
    data.resize(S, 0);
    image.extend(data);
    image.extend(directory(
        22,
        22,
        &[
            record(&ucs2("Dos"), 23, S as u32, true),
            record(&ucs2("ReadMe.txt;1"), 21, 5, false),
        ],
    ));
    image.extend(directory(23, 22, &[record(&ucs2("SC2000.dat;1"), 21, 3, false)]));
    image
}

/// The image with each 2048-byte sector inside a raw 2352-byte sector.
fn raw_image(cooked: &[u8], mode: u8) -> Vec<u8> {
    let offset = if mode == 1 { 16 } else { 24 };
    let mut raw = Vec::new();

    for sector in cooked.chunks(S) {
        let mut frame = vec![0u8; RAW_SECTOR as usize];
        frame[..12].copy_from_slice(&SYNC);
        frame[15] = mode;
        frame[offset..offset + S].copy_from_slice(sector);
        raw.extend(frame);
    }

    raw
}

fn listing(disc: &mut Disc<Cursor<Vec<u8>>>) -> Vec<(String, bool, u64)> {
    disc.entries()
        .unwrap()
        .into_iter()
        .map(|entry| (entry.path, entry.is_dir, entry.size))
        .collect()
}

#[test]
fn a_cooked_image_lists_and_reads_its_files() {
    let mut disc = Disc::new(Cursor::new(cooked_image(false)), None).unwrap();
    assert_eq!(disc.layout(), Layout::COOKED);
    assert!(!disc.is_joliet());
    assert_eq!(
        listing(&mut disc),
        [
            ("DOS".into(), true, S as u64),
            ("README.TXT".into(), false, 5),
            ("DOS/SC2000.DAT".into(), false, 3)
        ]
    );
    let entries = disc.entries().unwrap();
    assert_eq!(disc.read(&entries[1], 1024).unwrap(), b"hello");
    assert_eq!(disc.read(&entries[2], 1024).unwrap(), b"hel");
    assert!(disc.read(&entries[1], 4).is_err());
}

#[test]
fn joliet_names_have_priority() {
    let mut disc = Disc::new(Cursor::new(cooked_image(true)), None).unwrap();
    assert!(disc.is_joliet());
    let names: Vec<String> = listing(&mut disc).into_iter().map(|(path, _, _)| path).collect();
    assert_eq!(names, ["Dos", "ReadMe.txt", "Dos/SC2000.dat"]);
}

#[test]
fn raw_mode1_and_mode2_sectors_are_detected() {
    for (mode, layout) in [(1, Layout::MODE1_RAW), (2, Layout::MODE2_RAW)] {
        let mut disc = Disc::new(Cursor::new(raw_image(&cooked_image(false), mode)), None).unwrap();
        assert_eq!(disc.layout(), layout);
        let entries = disc.entries().unwrap();
        assert_eq!(disc.read(&entries[1], 1024).unwrap(), b"hello");
    }
}

#[test]
fn other_files_are_refused() {
    assert!(Disc::new(Cursor::new(vec![0u8; 40 * S]), None).is_err());
    assert!(Disc::new(Cursor::new(vec![1u8]), None).is_err());
    // a raw image of an unknown sector mode
    assert!(Disc::new(Cursor::new(raw_image(&cooked_image(false), 3)), None).is_err());
    // a directory whose records point past the end of the image
    let mut image = cooked_image(false);
    image.truncate(20 * S);
    let mut disc = Disc::new(Cursor::new(image), None).unwrap();
    assert!(disc.entries().is_err());
}

#[test]
fn a_directory_loop_is_refused() {
    let mut image = cooked_image(false);
    // DOS names the root folder as its child
    let looped = directory(20, 19, &[record(b"AGAIN", 19, S as u32, true)]);
    image[20 * S..21 * S].copy_from_slice(&looped);
    let mut disc = Disc::new(Cursor::new(image), None).unwrap();
    assert!(disc.entries().is_err());
}

#[test]
fn cue_sheets_name_the_first_data_track() {
    let sheet = "FILE \"Sim City 2000.bin\" BINARY\r\n  TRACK 01 MODE2/2352\r\n    INDEX 01 00:00:00\r\n";
    assert_eq!(
        parse_cue(sheet).unwrap(),
        Track {
            file: "Sim City 2000.bin".into(),
            layout: Layout::MODE2_RAW
        }
    );
    let sheet = "FILE game.bin BINARY\nTRACK 1 AUDIO\nTRACK 2 mode1/2352\n";
    assert_eq!(
        parse_cue(sheet).unwrap(),
        Track {
            file: "game.bin".into(),
            layout: Layout::MODE1_RAW
        }
    );
    assert!(parse_cue("FILE a.bin BINARY\nTRACK 01 AUDIO\n").is_err());
    assert!(parse_cue("TRACK 01 MODE1/2352\n").is_err());
}

#[test]
fn names_lose_their_version_suffix() {
    assert_eq!(clean_name("SIMCITY.EXE;1"), "SIMCITY.EXE");
    assert_eq!(clean_name("README.;1"), "README");
    assert_eq!(clean_name("A;B"), "A;B");
}
