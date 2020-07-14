use super::page::Pageable;
use gettextrs::gettext;
use gtk::prelude::*;

pub struct WelcomePageWidget {
    pub widget: gtk::Box,
    pub title: String,
}

impl Pageable for WelcomePageWidget {
    fn get_widget(&self) -> gtk::Widget {
        self.widget.clone().upcast::<gtk::Widget>()
    }

    fn get_title(&self) -> String {
        self.title.clone()
    }
}

impl WelcomePageWidget {
    pub fn new() -> Self {
        let widget = gtk::Box::new(gtk::Orientation::Vertical, 0);
        let welcome_page = Self {
            widget,
            title: gettext("Welcome Tour"),
        };

        welcome_page.init();
        welcome_page
    }

    fn init(&self) {
        self.widget.set_property_expand(true);
        self.widget.set_valign(gtk::Align::Center);
        self.widget.set_halign(gtk::Align::Center);
        self.widget.set_margin_top(24);
        self.widget.set_margin_bottom(24);

        let name = glib::get_os_info("NAME").unwrap_or("GNOME".into());
        let version = glib::get_os_info("VERSION").unwrap_or("3.36".into());
        let icon = glib::get_os_info("LOGO").unwrap_or("start-here-symbolic".into());

        let logo = gtk::Image::from_icon_name(Some(&icon), gtk::IconSize::Dialog);
        logo.set_pixel_size(196);
        logo.show();
        self.widget.add(&logo);

        let title = gtk::Label::new(Some(&gettext(format!("Welcome to {} {}", name, version))));
        title.set_margin_top(36);
        title.get_style_context().add_class("large-title");
        title.show();
        self.widget.add(&title);

        let text = gtk::Label::new(Some(&gettext("Hi there! Take the tour to learn your way around and discover essential features.")));
        text.get_style_context().add_class("body");
        text.set_margin_top(12);
        text.show();
        self.widget.add(&text);

        let actions_container = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        actions_container.set_halign(gtk::Align::Center);
        actions_container.set_margin_top(36);

        let skip_tour_btn = gtk::Button::with_label(&gettext("_No Thanks"));
        skip_tour_btn.set_property_height_request(40);
        skip_tour_btn.set_property_width_request(180);
        skip_tour_btn.set_use_underline(true);
        skip_tour_btn.set_action_name(Some("app.skip-tour"));
        skip_tour_btn.show();
        actions_container.add(&skip_tour_btn);

        let start_tour_btn = gtk::Button::with_label(&gettext("_Start Tour"));
        start_tour_btn.set_property_height_request(40);
        start_tour_btn.set_property_width_request(180);
        start_tour_btn.set_use_underline(true);
        start_tour_btn.set_action_name(Some("app.start-tour"));
        start_tour_btn.get_style_context().add_class("suggested-action");
        start_tour_btn.show();
        actions_container.add(&start_tour_btn);
        actions_container.set_focus_child(Some(&start_tour_btn));

        actions_container.show();

        self.widget.add(&actions_container);
        self.widget.show();
    }
}
