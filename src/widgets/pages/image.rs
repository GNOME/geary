use gtk::prelude::*;

pub struct ImagePageWidget {
    pub widget: gtk::Box,
}

impl ImagePageWidget {
    pub fn new(resource_uri: &str, text: &str) -> Self {
        let widget = gtk::Box::new(gtk::Orientation::Vertical, 48);

        let image_page = Self { widget };

        image_page.init(resource_uri, text);
        image_page
    }

    fn init(&self, resource_uri: &str, text: &str) {
        self.widget.set_halign(gtk::Align::Center);
        self.widget.set_valign(gtk::Align::Center);
        self.widget.set_property_margin(48);

        let image = gtk::Picture::new_for_resource(Some(resource_uri));
        image.set_valign(gtk::Align::Start);
        self.widget.add(&image);

        let label = gtk::Label::new(Some(text));
        label.set_lines(2);
        label.set_property_wrap(true);
        label.set_justify(gtk::Justification::Center);
        label.set_valign(gtk::Align::Center);
        label.get_style_context().add_class("page-head");
        self.widget.add(&label);
    }
}
