use gettextrs::gettext;
use gtk::prelude::*;
use libhandy::prelude::HeaderBarExt;

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
        self.widget.set_property_expand(true);

        let container = gtk::Box::new(gtk::Orientation::Vertical, 0);
        container.set_property_expand(true);
        container.set_valign(gtk::Align::Center);
        container.set_halign(gtk::Align::Center);
        container.set_margin_top(24);
        container.set_margin_bottom(24);

        let name = glib::get_os_info("NAME").unwrap_or("GNOME".into());
        let version = glib::get_os_info("VERSION").unwrap_or("3.36".into());
        let icon = glib::get_os_info("LOGO").unwrap_or("start-here-symbolic".into());

        let logo = gtk::Image::from_icon_name(Some(&icon), gtk::IconSize::Dialog);
        logo.set_pixel_size(196);
        container.add(&logo);

        let title = gtk::Label::new(Some(&gettext(format!("Welcome to {} {}", name, version))));
        title.set_margin_top(36);
        title.get_style_context().add_class("large-title");
        container.add(&title);

        let text = gtk::Label::new(Some(&gettext("Hi there! If you are new to GNOME, you can take the tour to learn some essential features.")));
        text.get_style_context().add_class("body");
        text.set_margin_top(12);
        container.add(&text);

        let actions_container = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        actions_container.set_halign(gtk::Align::Center);
        actions_container.set_margin_top(36);

        let start_tour_btn = gtk::Button::with_label(&gettext("_Take the Tour"));
        start_tour_btn.get_style_context().add_class("suggested-action");
        start_tour_btn.set_property_height_request(40);
        start_tour_btn.set_property_width_request(180);
        start_tour_btn.set_use_underline(true);
        start_tour_btn.set_action_name(Some("app.start-tour"));

        let skip_tour_btn = gtk::Button::with_label(&gettext("_No Thanks"));
        skip_tour_btn.set_property_height_request(40);
        skip_tour_btn.set_property_width_request(180);
        skip_tour_btn.set_use_underline(true);
        skip_tour_btn.set_action_name(Some("app.skip-tour"));

        actions_container.add(&skip_tour_btn);
        actions_container.add(&start_tour_btn);
        actions_container.set_focus_child(Some(&start_tour_btn));

        container.add(&actions_container);

        let headerbar = libhandy::HeaderBar::new();
        headerbar.set_show_close_button(true);
        headerbar.set_title(Some(&gettext("Welcome Tour")));

        self.widget.add(&headerbar);
        self.widget.add(&container);
    }
}
