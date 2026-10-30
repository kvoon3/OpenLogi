//! Manual smoke-test for the Screenflare action group.
//!
//! Fires one [`Action::Screenflare*`] through the same dispatch path a button
//! press takes (`openlogi_inject::execute`), so the whole chain can be checked
//! without a mouse: `Action` → `Effect::Screenflare` → `screenflarex://<id>` →
//! ScreenflareX performs its own menu item.
//!
//! # Usage
//!
//! ```text
//! cargo run --example screenflare -p openlogi-inject -- capture-fullscreen
//! cargo run --example screenflare -p openlogi-inject -- toggle
//! ```
//!
//! Argument names are the action ids `screenflarex://` answers to. `toggle` needs nothing
//! running to be useful: with no recording it starts one, so run it twice to see
//! start then stop.

use openlogi_core::binding::Action;
use openlogi_inject::execute;

fn action_for(command: &str) -> Option<Action> {
    Some(match command {
        "capture-area" => Action::ScreenflareCaptureArea,
        "capture-window" => Action::ScreenflareCaptureWindow,
        "capture-fullscreen" => Action::ScreenflareCaptureFullscreen,
        "capture-scrolling" => Action::ScreenflareCaptureScrolling,
        "capture-text" => Action::ScreenflareCaptureText,
        "record-display" => Action::ScreenflareRecordDisplay,
        "record-window" => Action::ScreenflareRecordWindow,
        "record-area" => Action::ScreenflareRecordArea,
        "toggle" => Action::ScreenflareToggleRecording,
        "stop-recording" => Action::ScreenflareStopRecording,
        _ => return None,
    })
}

fn main() {
    let mut args = std::env::args().skip(1);
    let Some(command) = args.next() else {
        eprintln!(
            "usage: screenflare <capture-area|capture-window|capture-fullscreen|capture-scrolling|capture-text|record-display|record-window|record-area|toggle|stop-recording>"
        );
        std::process::exit(2);
    };
    let Some(action) = action_for(&command) else {
        eprintln!("unknown screenflare command: {command}");
        std::process::exit(2);
    };
    println!("dispatching {action:?}");
    execute(&action);
    println!("dispatched; ScreenflareX performs it in its own process");
}
