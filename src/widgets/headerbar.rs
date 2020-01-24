use gtk::prelude::*;

pub struct Headerbar {
    pub widget: gtk::HeaderBar,
}

impl Headerbar {
    pub fn new() -> Self {
        let widget = gtk::HeaderBar::new();

        widget.set_show_title_buttons(true);

        Self { widget }
    }
}
