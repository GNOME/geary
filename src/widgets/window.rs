use gettextrs::gettext;
use gtk::prelude::*;
use std::cell::RefCell;
use std::rc::Rc;

use super::pages::{ImagePageWidget, WelcomePageWidget};
use super::paginator::PaginatorWidget;
use crate::config::PROFILE;
use libhandy::prelude::DeckExt;

pub struct Window {
    pub widget: libhandy::ApplicationWindow,
    deck: libhandy::Deck,
    pub paginator: RefCell<Rc<PaginatorWidget>>,
    welcome_page: WelcomePageWidget,
}

impl Window {
    pub fn new(app: &gtk::Application) -> Self {
        let widget = libhandy::ApplicationWindow::new();
        widget.set_application(Some(app));

        let deck = libhandy::Deck::new();
        let paginator = RefCell::new(PaginatorWidget::new());

        let mut window_widget = Window {
            widget,
            deck,
            welcome_page: WelcomePageWidget::new(),
            paginator,
        };

        window_widget.init();
        window_widget
    }

    pub fn start_tour(&self) {
        self.deck.set_visible_child(&self.paginator.borrow().widget);
        self.paginator.borrow_mut().set_page(0);
    }

    pub fn stop_tour(&self) {
        self.paginator.borrow_mut().set_page(0);
        self.deck.set_visible_child(&self.welcome_page.widget);
    }

    fn init(&mut self) {
        self.widget.set_default_size(920, 640);
        self.deck.set_transition_type(libhandy::DeckTransitionType::Slide);
        self.deck.set_transition_duration(300);
        self.deck.set_can_swipe_back(true);
        self.deck.set_can_swipe_forward(true);

        // Devel Profile
        if PROFILE == "Devel" {
            self.widget.get_style_context().add_class("devel");
        }

        self.deck.add(&self.welcome_page.widget);

        self.paginator.borrow_mut().add_page(Box::new(ImagePageWidget::new(
            "/org/gnome/Tour/activities.svg",
            gettext("Activities Overview"),
            gettext("Open Activities to start apps"),
            gettext("You can also view open windows, search and use workspaces."),
        )));

        self.paginator.borrow_mut().add_page(Box::new(ImagePageWidget::new(
            "/org/gnome/Tour/search.svg",
            gettext("Search"),
            gettext("In the Activities Overview, just start typing to search"),
            gettext("Search can be used to launch apps, find settings, do calculations and much more."),
        )));

        self.paginator.borrow_mut().add_page(Box::new(ImagePageWidget::new(
            "/org/gnome/Tour/calendar.svg",
            gettext("Date & Time"),
            gettext("Click the time to see your now and next"),
            gettext("This includes notifications, media controls, calendar events, the weather and world clocks."),
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
            gettext("Find and install apps"),
            gettext("The Software app makes it easy to find and install all the apps you need."),
        )));

        let last_page = ImagePageWidget::new(
            "/org/gnome/Tour/ready-to-go.svg",
            gettext("Learn More"),
            gettext("That's it! To learn more, see the Help"),
            gettext("The help app contains information, tips and tricks."),
        );
        last_page.widget.get_style_context().add_class("last-page");
        self.paginator.borrow_mut().add_page(Box::new(last_page));

        self.deck.add(&self.paginator.borrow().widget);
        self.widget.add(&self.deck);
    }
}
