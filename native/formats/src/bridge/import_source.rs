//! The source scan of the game importer.

use godot::prelude::*;
use sc2k_assets::import::source::{self, Source};
use sc2k_assets::import::unpack;
use std::path::Path;

fn texts(values: &[String]) -> PackedStringArray {
    values.iter().map(|value| GString::from(value.as_str())).collect()
}

/// The source scan of the game importer.
#[derive(GodotClass)]
#[class(base=Object, no_init)]
pub struct NativeImportSource {}

#[godot_api]
impl NativeImportSource {
    /// `{platform, warnings, notes, error, root, names, kinds, ids, sources,
    /// payloads}` of an asset file or game folder at an absolute, simplified path.
    #[func]
    fn scan(path: GString) -> VarDictionary {
        let scanned = Source::scan(&path.to_string());
        let records = &scanned.records;
        let mut payloads = VarArray::new();

        for record in records {
            payloads.push(&PackedByteArray::from(record.bytes.as_slice()).to_variant());
        }

        let mut result = VarDictionary::new();
        result.set("platform", scanned.platform.as_str());
        result.set("warnings", &texts(&scanned.warnings));
        result.set("notes", &texts(&scanned.notes));
        result.set("error", scanned.error.as_str());
        result.set("root", scanned.root.as_str());
        result.set(
            "names",
            &records
                .iter()
                .map(|record| GString::from(record.name.as_str()))
                .collect::<PackedStringArray>(),
        );
        result.set(
            "kinds",
            &records
                .iter()
                .map(|record| GString::from(record.kind.as_str()))
                .collect::<PackedStringArray>(),
        );
        result.set("ids", &records.iter().map(|record| record.id).collect::<PackedInt64Array>());
        result.set(
            "sources",
            &records
                .iter()
                .map(|record| GString::from(record.source.as_str()))
                .collect::<PackedStringArray>(),
        );
        result.set("payloads", &payloads);
        result
    }

    /// "disc" for a disc image, "zip" for a ZIP archive, or "" for a folder or
    /// another file. See `import/unpack.rs` of `sc2k_assets`.
    #[func]
    fn packed_kind(path: GString) -> GString {
        GString::from(unpack::kind(Path::new(&path.to_string())).unwrap_or(""))
    }

    /// `{ok, error, files, skipped}`. Writes the files of a disc image or ZIP
    /// archive below `folder`, which must not exist yet.
    #[func]
    fn unpack(path: GString, folder: GString) -> VarDictionary {
        let mut result = VarDictionary::new();

        match unpack::unpack(Path::new(&path.to_string()), Path::new(&folder.to_string())) {
            Ok(unpacked) => {
                result.set("ok", true);
                result.set("error", "");
                result.set("files", unpacked.files as i64);
                result.set("skipped", &texts(&unpacked.skipped));
            }
            Err(error) => {
                result.set("ok", false);
                result.set("error", error.as_str());
                result.set("files", 0);
                result.set("skipped", &PackedStringArray::new());
            }
        }

        result
    }

    /// The file name without an ISO 9660 version suffix or a final dot.
    #[func]
    fn original_name(name: GString) -> GString {
        GString::from(source::original_name(&name.to_string()).as_str())
    }
}
