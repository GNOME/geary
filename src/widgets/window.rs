use gio::prelude::*;
use glib::subclass;
use glib::subclass::prelude::*;
use glib::translate::*;
use gtk::prelude::*;
use gtk::subclass::prelude::{ApplicationWindowImpl, BinImpl, ContainerImpl, WidgetImpl, WindowImpl};
use std::cell::RefCell;

use super::headerbar::HeaderBar;
use super::pages::{ImagePageWidget, WelcomePageWidget};
use super::paginator::PaginatorWidget;
use crate::application::Application;
use crate::config::PROFILE;
use crate::utils;

pub struct ApplicationWindowPrivate {
    headerbar: HeaderBar,
    paginator: RefCell<PaginatorWidget>,
    container: gtk::Stack,
}

impl ObjectSubclass for ApplicationWindowPrivate {
    const NAME: &'static str = "ApplicationWindowPrivate";
    type ParentType = gtk::ApplicationWindow;
    type Instance = subclass::simple::InstanceStruct<Self>;
    type Class = subclass::simple::ClassStruct<Self>;

    glib_object_subclass!();

    fn new() -> Self {
        let headerbar = HeaderBar::new();
        let paginator = RefCell::new(PaginatorWidget::new());
        let container = gtk::Stack::new();

        Self { headerbar, paginator, container }
    }
}

// Implement GLib.OBject for ApplicationWindow
impl ObjectImpl for ApplicationWindowPrivate {
    glib_object_impl!();

    fn constructed(&self, obj: &glib::Object) {
        self.parent_constructed(obj);

        let self_ = obj.downcast_ref::<ApplicationWindow>().unwrap();
        self_.set_default_size(920, 640);
        self.container.set_transition_type(gtk::StackTransitionType::SlideLeftRight);
        self.container.set_transition_duration(300);

        // Devel Profile
        if PROFILE == "Devel" {
            self_.get_style_context().add_class("devel");
        }

        self_.set_titlebar(Some(&self.headerbar.widget));

        let welcome_page = WelcomePageWidget::new();
        self.container.add_named(&welcome_page.widget, "welcome");

        self.paginator
            .borrow_mut()
            .add_page(ImagePageWidget::new("/org/gnome/Tour/activities.svg", "Click Activities to view windows, launch apps and search"));
        self.paginator
            .borrow_mut()
            .add_page(ImagePageWidget::new("/org/gnome/Tour/search.svg", "In the Activities Overview, just start typing to search"));
        self.paginator
            .borrow_mut()
            .add_page(ImagePageWidget::new("/org/gnome/Tour/calendar.svg", "Click the time to view the calendar, notifications and weather"));
        self.paginator.borrow_mut().add_page(ImagePageWidget::new(
            "/org/gnome/Tour/status-menu.svg",
            "Use the status menu to view system information and access settings",
        ));
        self.paginator
            .borrow_mut()
            .add_page(ImagePageWidget::new("/org/gnome/Tour/software.svg", "Use the Software app to find and install apps"));
        self.container.add_named(&self.paginator.borrow().widget, "pages");

        self_.add(&self.container);
    }
}

// Implement Gtk.Widget for ApplicationWindow
impl WidgetImpl for ApplicationWindowPrivate {}

// Implement Gtk.Container for ApplicationWindow
impl ContainerImpl for ApplicationWindowPrivate {}

// Implement Gtk.Bin for ApplicationWindow
impl BinImpl for ApplicationWindowPrivate {}

// Implement Gtk.Window for ApplicationWindow
impl WindowImpl for ApplicationWindowPrivate {}

// Implement Gtk.ApplicationWindow for ApplicationWindow
impl ApplicationWindowImpl for ApplicationWindowPrivate {}

// Wrap ApplicationWindowPrivate into a usable gtk-rs object
glib_wrapper! {
    pub struct ApplicationWindow(
        Object<subclass::simple::InstanceStruct<ApplicationWindowPrivate>,
        subclass::simple::ClassStruct<ApplicationWindowPrivate>,
        SwApplicationWindowClass>)
        @extends gtk::Widget, gtk::Container, gtk::Bin, gtk::Window, gtk::ApplicationWindow;

    match fn {
        get_type => || ApplicationWindowPrivate::get_type().to_glib(),
    }
}

impl ApplicationWindow {
    pub fn new(app: &Application) -> Self {
        let window = glib::Object::new(ApplicationWindow::static_type(), &[("application", app)])
            .unwrap()
            .downcast::<ApplicationWindow>()
            .unwrap();

        window.setup_gactions();
        window
    }

    pub fn start_tour(&self) {
        let self_ = ApplicationWindowPrivate::from_instance(self);

        self_.container.set_visible_child_name("pages");
        self_.headerbar.start_tour();
    }

    pub fn end_tour(&self) {
        let self_ = ApplicationWindowPrivate::from_instance(self);
        self_.container.set_visible_child_name("welcome");
        self_.headerbar.end_tour();
    }

    pub fn next_page(&self) {
        let self_ = ApplicationWindowPrivate::from_instance(self);

        let total_pages = self_.paginator.borrow().get_total_pages();
        let current_page = self_.paginator.borrow().get_current_page();
        self_.headerbar.set_page_nr(current_page + 1, total_pages);

        if current_page == total_pages {
            self.destroy();
        } else {
            self_.paginator.borrow().next();
        }
    }

    pub fn previous_page(&self) {
        let self_ = ApplicationWindowPrivate::from_instance(self);
        let total_pages = self_.paginator.borrow().get_total_pages();
        let current_page = self_.paginator.borrow().get_current_page();
        self_.headerbar.set_page_nr(current_page - 1, total_pages);

        match current_page {
            1 => self.end_tour(),
            _ => self_.paginator.borrow().previous(),
        }
    }

    fn setup_gactions(&self) {
        let window = self.clone().upcast::<gtk::ApplicationWindow>();
        let app = window.get_application().unwrap();

        // Quit
        utils::action(
            &app,
            "quit",
            clone!(@strong app => move |_, _| {
                app.quit();
            }),
        );
        // Start Tour
        utils::action(
            &app,
            "start-tour",
            clone!(@strong self as window => move |_, _| {
                window.start_tour();
            }),
        );

        // Skip Tour
        utils::action(
            &app,
            "skip-tour",
            clone!(@strong app => move |_, _| {
                app.quit();
            }),
        );

        utils::action(
            &app,
            "next-page",
            clone!(@strong self as window => move |_, _| {
                window.next_page();
            }),
        );
        utils::action(
            &app,
            "previous-page",
            clone!(@strong self as window => move |_, _| {
                window.previous_page();
            }),
        );
        app.set_accels_for_action("app.quit", &["<primary>q"]);
    }
}
