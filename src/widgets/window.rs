use gettextrs::gettext;
use gtk::prelude::*;
use std::cell::RefCell;
use std::rc::Rc;

use super::pages::{ImagePageWidget, WelcomePageWidget};
use super::paginator::PaginatorWidget;
use crate::config::{APP_ID, PROFILE};

pub struct Window {
    pub widget: libhandy::ApplicationWindow,
    pub paginator: RefCell<Rc<PaginatorWidget>>,
}

impl Window {
    pub fn new(app: &gtk::Application) -> Self {
        let widget = libhandy::ApplicationWindow::new();
        widget.set_application(Some(app));

        let paginator = RefCell::new(PaginatorWidget::new());

        let mut window_widget = Window { widget, paginator };

        window_widget.init();
        window_widget
    }

    pub fn start_tour(&self) {
        self.paginator.borrow_mut().set_page(1);
    }

    pub fn reset_tour(&self) {
        self.paginator.borrow_mut().set_page(0);
    }

    fn init(&mut self) {
        self.widget.set_default_size(920, 640);
        self.widget.set_icon_name(Some(APP_ID));

        // Devel Profile
        if PROFILE == "Devel" {
            self.widget.get_style_context().add_class("devel");
        }

        self.paginator.borrow_mut().add_page(Box::new(WelcomePageWidget::new()));

        self.paginator.borrow_mut().add_page(Box::new(ImagePageWidget::new(
            "/org/gnome/Tour/activities.svg",
            gettext("Activities Overview"),
            gettext("Open Activities to launch apps"),
            gettext("The activities view can also be used to switch windows and search."),
        )));

        self.paginator.borrow_mut().add_page(Box::new(ImagePageWidget::new(
            "/org/gnome/Tour/search.svg",
            gettext("Search"),
            gettext("Just type to search"),
            gettext("In the activities view, just start tying to search for apps, settings and more."),
        )));

        self.paginator.borrow_mut().add_page(Box::new(ImagePageWidget::new(
            "/org/gnome/Tour/calendar.svg",
            gettext("Date & Time"),
            gettext("Click the time to see notifications"),
            gettext("The notifications popover also includes personal planning tools."),
        )));

        self.paginator.borrow_mut().add_page(Box::new(ImagePageWidget::new(
            "/org/gnome/Tour/status-menu.svg",
            gettext("System Menu"),
            gettext("View system information and settings"),
            gettext("Get an overview of the system status and quickly change settings."),
        )));
        self.paginator.borrow_mut().add_page(Box::new(ImagePageWidget::new(
            "/org/gnome/Tour/software.svg",
            gettext("Software"),
            gettext("Use Software to find and install apps"),
            gettext("Discover great apps through search, browsing and our recommendations."),
        )));

        let last_page = ImagePageWidget::new(
            "/org/gnome/Tour/ready-to-go.svg",
            gettext("Tour Completed"),
            gettext("That's it! We hope that you enjoy NAME OF DISTRO."),
            gettext("To get more advice and tips, see the Help app."),
        );
        last_page.widget.get_style_context().add_class("last-page");
        self.paginator.borrow_mut().add_page(Box::new(last_page));

        self.widget.add(&self.paginator.borrow().widget);
    }
}
