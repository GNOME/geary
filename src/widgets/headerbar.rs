use gettextrs::gettext;
use gtk::prelude::*;

pub struct HeaderBar {
    pub widget: gtk::Stack,
    headerbar: gtk::HeaderBar,
    next_btn: gtk::Button,
}

impl HeaderBar {
    pub fn new() -> Self {
        let widget = gtk::Stack::new();
        let headerbar = gtk::HeaderBar::new();
        let next_btn = gtk::Button::new();

        let headerbar = Self { widget, headerbar, next_btn };
        headerbar.init();
        headerbar
    }

    pub fn start_tour(&self) {
        self.widget.set_visible_child_name("pages");
        self.headerbar.set_show_title_buttons(false);
    }

    pub fn set_page_nr(&self, page_nr: i32, total_pages: i32) {
        if page_nr == total_pages {
            self.next_btn.set_label(&gettext("Close"));
        } else {
            self.next_btn.set_label(&gettext("Next"));
        }
    }

    pub fn set_page_title(&self, title: &str) {
        self.headerbar.set_title(Some(title));
    }

    pub fn end_tour(&self) {
        self.widget.set_visible_child_name("welcome");
        self.headerbar.set_show_title_buttons(true);
    }

    fn init(&self) {
        self.headerbar.set_show_title_buttons(true);
        self.widget.set_hexpand(true);
        self.widget.set_transition_type(gtk::StackTransitionType::SlideLeftRight);
        self.widget.set_transition_duration(300);
        self.widget.get_style_context().add_class("titlebar");

        let container = gtk::HeaderBar::new();
        container.set_show_title_buttons(true);
        container.set_title(Some(&gettext("Welcome Tour")));
        self.widget.add_named(&container, "welcome");

        let previous_btn = gtk::Button::new();
        previous_btn.add(&gtk::Label::new(Some("Previous")));
        previous_btn.set_halign(gtk::Align::Start);
        previous_btn.set_action_name(Some("app.previous-page"));
        previous_btn.set_hexpand(true);
        previous_btn.set_property_width_request(60);

        self.next_btn.add(&gtk::Label::new(Some(&gettext("Next"))));
        self.next_btn.get_style_context().add_class("suggested-action");
        self.next_btn.set_action_name(Some("app.next-page"));
        self.next_btn.set_halign(gtk::Align::End);
        self.next_btn.set_hexpand(true);
        self.next_btn.set_property_width_request(60);

        self.headerbar.pack_start(&previous_btn);
        self.headerbar.pack_end(&self.next_btn);
        self.widget.add_named(&self.headerbar, "pages");
    }
}
