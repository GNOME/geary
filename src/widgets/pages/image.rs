use super::page::Pageable;
use gtk::prelude::*;

pub struct ImagePageWidget {
    pub widget: gtk::Box,
    resource_uri: String,
    pub title: String,
    pub head: String,
    pub body: String,
}

impl Pageable for ImagePageWidget {
    fn get_widget(&self) -> gtk::Widget {
        self.widget.clone().upcast::<gtk::Widget>()
    }

    fn get_title(&self) -> String {
        self.title.clone()
    }

    fn get_head(&self) -> String {
        self.head.clone()
    }

    fn get_body(&self) -> String {
        self.body.clone()
    }
}

impl ImagePageWidget {
    pub fn new(resource_uri: &str, title: String, head: String, body: String) -> Self {
        let widget = gtk::Box::new(gtk::Orientation::Vertical, 12);

        let image_page = Self {
            widget,
            resource_uri: resource_uri.to_string(),
            title,
            head,
            body,
        };

        image_page.init();
        image_page
    }

    fn init(&self) {
        self.widget.set_halign(gtk::Align::Center);
        self.widget.set_valign(gtk::Align::Center);
        self.widget.set_property_margin(48);

        let image = gtk::Picture::new_for_resource(Some(&self.resource_uri));
        image.set_valign(gtk::Align::Start);
        self.widget.add(&image);

        let head_label = gtk::Label::new(Some(&self.get_head()));
        head_label.set_justify(gtk::Justification::Center);
        head_label.set_valign(gtk::Align::Center);
        head_label.set_margin_top(36);
        head_label.get_style_context().add_class("page-title");

        self.widget.add(&head_label);

        let body_label = gtk::Label::new(Some(&self.get_body()));
        body_label.set_lines(2);
        body_label.set_property_wrap(true);
        body_label.set_justify(gtk::Justification::Center);
        body_label.set_valign(gtk::Align::Center);
        body_label.get_style_context().add_class("page-body");
        body_label.set_margin_top(12);
        self.widget.add(&body_label);
    }
}
