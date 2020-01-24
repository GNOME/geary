use gtk::prelude::*;

use super::headerbar::Headerbar;
use super::pages::WelcomePageWidget;
use crate::config::PROFILE;

pub struct Window {
    pub widget: gtk::ApplicationWindow,
}

impl Window {
    pub fn new(app: &gtk::Application) -> Self {
        let widget = gtk::ApplicationWindow::new(app);

        let window_widget = Window { widget };

        window_widget.init();
        window_widget
    }

    fn init(&self) {
        self.widget.set_default_size(920, 640);

        // Devel Profile
        if PROFILE == "Devel" {
            self.widget.get_style_context().add_class("devel");
        }

        let headerbar = Headerbar::new();
        self.widget.set_titlebar(Some(&headerbar.widget));

        let container = gtk::Stack::new();

        let welcome_page = WelcomePageWidget::new();
        container.add_named(&welcome_page.widget, "welcome");

        self.widget.add(&container);
    }
}
