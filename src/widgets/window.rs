use gtk::prelude::*;

use super::headerbar::HeaderBar;
use super::pages::{ImagePageWidget, WelcomePageWidget};
use super::paginator::PaginatorWidget;
use crate::config::PROFILE;

pub struct Window {
    pub widget: gtk::ApplicationWindow,
    container: gtk::Stack,
    headerbar: HeaderBar,
    paginator: PaginatorWidget,
}

impl Window {
    pub fn new(app: &gtk::Application) -> Self {
        let widget = gtk::ApplicationWindow::new(app);
        let container = gtk::Stack::new();
        let headerbar = HeaderBar::new();
        let paginator = PaginatorWidget::new();

        let mut window_widget = Window {
            widget,
            container,
            headerbar,
            paginator,
        };

        window_widget.init();
        window_widget
    }

    pub fn start_tour(&self) {
        self.container.set_visible_child_name("pages");
        self.headerbar.start_tour();
    }

    pub fn next_page(&self) {
        self.paginator.next();
    }

    pub fn previous_page(&self) {
        self.paginator.previous();
    }

    fn init(&mut self) {
        self.widget.set_default_size(920, 640);
        self.container.set_transition_type(gtk::StackTransitionType::SlideLeftRight);
        self.container.set_transition_duration(300);

        // Devel Profile
        if PROFILE == "Devel" {
            self.widget.get_style_context().add_class("devel");
        }

        self.widget.set_titlebar(Some(&self.headerbar.widget));

        let welcome_page = WelcomePageWidget::new();
        self.container.add_named(&welcome_page.widget, "welcome");

        self.paginator
            .add_page(ImagePageWidget::new("/org/gnome/Tour/activities.svg", "Click Activities to view windows, launch apps and search"));
        self.paginator
            .add_page(ImagePageWidget::new("/org/gnome/Tour/search.svg", "In the Activities Overview, just start typing to search"));
        self.paginator
            .add_page(ImagePageWidget::new("/org/gnome/Tour/calendar.svg", "Click the time to view the calendar, notifications and weather"));
        self.paginator.add_page(ImagePageWidget::new(
            "/org/gnome/Tour/status-menu.svg",
            "Use the status menu to view system information and access settings",
        ));
        self.paginator
            .add_page(ImagePageWidget::new("/org/gnome/Tour/software.svg", "Use the Software app to find and install apps"));
        self.container.add_named(&self.paginator.widget, "pages");

        self.widget.add(&self.container);
    }
}
