use gtk::prelude::*;

pub struct WelcomePageWidget {
    pub widget: gtk::Box,
}

impl WelcomePageWidget {
    pub fn new() -> Self {
        let widget = gtk::Box::new(gtk::Orientation::Vertical, 0);

        let welcome_page = Self { widget };

        welcome_page.init();
        welcome_page
    }

    fn init(&self) {
        self.widget.set_valign(gtk::Align::Center);
        self.widget.set_halign(gtk::Align::Center);
        self.widget.set_margin_top(24);
        self.widget.set_margin_bottom(24);

        let logo = gtk::Image::new_from_icon_name(Some("start-here-symbolic"));
        logo.set_pixel_size(196);
        self.widget.add(&logo);

        let title = gtk::Label::new(Some("Welcome to GNOME 3.34"));
        title.set_margin_top(36);
        title.get_style_context().add_class("large-title");
        self.widget.add(&title);

        let text = gtk::Label::new(Some("Take the tour to learn some essential fatures. It only takes a minute."));
        text.get_style_context().add_class("body");
        text.set_margin_top(12);
        self.widget.add(&text);

        let actions_container = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        actions_container.set_halign(gtk::Align::Center);
        actions_container.set_margin_top(36);

        let start_tour_btn = gtk::Button::new();
        start_tour_btn.add(&gtk::Label::new(Some("Take the Tour")));
        start_tour_btn.get_style_context().add_class("suggested-action");
        start_tour_btn.set_property_height_request(40);
        start_tour_btn.set_property_width_request(180);

        let skip_tour_btn = gtk::Button::new();
        skip_tour_btn.add(&gtk::Label::new(Some("Skip")));
        skip_tour_btn.set_property_height_request(40);
        skip_tour_btn.set_property_width_request(180);
        skip_tour_btn.set_action_name(Some("app.skip-tour"));

        actions_container.add(&skip_tour_btn);
        actions_container.add(&start_tour_btn);

        self.widget.add(&actions_container);
    }
}
