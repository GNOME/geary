use gtk::prelude::*;

#[derive(Debug)]
pub struct HeaderBar {
    pub widget: gtk::HeaderBar,
    container: gtk::Stack,
    next_btn: gtk::Button,
}

impl HeaderBar {
    pub fn new() -> Self {
        let widget = gtk::HeaderBar::new();
        let container = gtk::Stack::new();
        let next_btn = gtk::Button::new();

        widget.set_show_title_buttons(true);

        let headerbar = Self { widget, container, next_btn };
        headerbar.init();
        headerbar
    }

    pub fn start_tour(&self) {
        self.container.set_visible_child_name("pages");
        self.widget.set_show_title_buttons(false);
    }

    pub fn set_page_nr(&self, page_nr: i32, total_pages: i32) {
        if page_nr == total_pages {
            self.next_btn.set_label("Done");
        } else {
            self.next_btn.set_label("Next");
        }
    }

    pub fn end_tour(&self) {
        self.container.set_visible_child_name("welcome");
        self.widget.set_show_title_buttons(true);
    }

    fn init(&self) {
        self.container.set_hexpand(true);
        self.container.set_transition_type(gtk::StackTransitionType::SlideLeftRight);
        self.container.set_transition_duration(300);
        self.container.add_named(&gtk::Label::new(None), "welcome");

        let pages_container = gtk::Box::new(gtk::Orientation::Horizontal, 0);

        let previous_btn = gtk::Button::new();
        previous_btn.add(&gtk::Label::new(Some("Previous")));
        previous_btn.set_halign(gtk::Align::Start);
        previous_btn.set_action_name(Some("app.previous-page"));
        previous_btn.set_hexpand(true);
        previous_btn.set_property_width_request(60);

        self.next_btn.add(&gtk::Label::new(Some("Next")));
        self.next_btn.get_style_context().add_class("suggested-action");
        self.next_btn.set_action_name(Some("app.next-page"));
        self.next_btn.set_halign(gtk::Align::End);
        self.next_btn.set_hexpand(true);
        self.next_btn.set_property_width_request(60);

        pages_container.add(&previous_btn);
        pages_container.add(&self.next_btn);
        self.container.add_named(&pages_container, "pages");

        self.widget.set_custom_title(Some(&self.container));
    }
}
