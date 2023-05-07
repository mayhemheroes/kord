#![no_main]

use klib::core::base::Parsable;
use klib::core::chord::*;
use klib::core::known_chord::HasRelativeChord;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: (u8, &str)| {
    let (op, input) = data;
    match Chord::parse(input) {
        Ok(c) => match op {
            0 => {
                c.chord();
            }
            1 => {
                c.scale();
            }
            2 => {
                c.relative_chord();
            }
            _ => (),
        },
        _ => (),
    }
});
