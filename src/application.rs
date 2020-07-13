use crate::config;
use crate::utils;
use crate::widgets::Window;
use gio::prelude::*;
use gtk::prelude::*;
use std::env;
use std::{cell::RefCell, rc::Rc};

pub struct Application {
    app: gtk::Application,
    window: RefCell<Rc<Option<Window>>>,
}

impl Application {
    pub fn new() -> Rc<Self> {
        let app = gtk::Application::new(Some(config::APP_ID), gio::ApplicationFlags::FLAGS_NONE).unwrap();

        let application = Rc::new(Self {
            app,
            window: RefCell::new(Rc::new(None)),
        });

        application.setup_signals(application.clone());
        application
    }

    fn setup_gactions(&self, application: Rc<Self>) {
        // Quit
        utils::action(
            &self.app,
            "quit",
            clone!(@strong self.app as app => move |_, _| {
                app.quit();
            }),
        );
        // Start Tour
        utils::action(
            &self.app,
            "start-tour",
            clone!(@strong application => move |_, _| {
                if let Some(window) = &*application.window.borrow().clone() {
                    window.start_tour();
                }
            }),
        );

        // Skip Tour
        utils::action(
            &self.app,
            "skip-tour",
            clone!(@strong self.app as app => move |_, _| {
                app.quit();
            }),
        );

        utils::action(
            &self.app,
            "next-page",
            clone!(@strong application => move |_, _| {
                if let Some(window) = &*application.window.borrow().clone() {
                    if window.paginator.borrow_mut().next().is_err() {
                        window.widget.close();
                    }
                }
            }),
        );
        utils::action(
            &self.app,
            "previous-page",
            clone!(@strong application => move |_, _| {
                if let Some(window) = &*application.window.borrow().clone() {
                    if window.paginator.borrow_mut().previous().is_err() {
                        window.reset_tour();
                    }
                }
            }),
        );
        self.app.set_accels_for_action("app.quit", &["<primary>q"]);
    }

    fn setup_signals(&self, app: Rc<Self>) {
        self.app.connect_startup(clone!(@weak app => move |_| {
            libhandy::init();
            app.setup_css();
            app.setup_gactions(app.clone());
        }));
        self.app.connect_activate(clone!(@weak app => move |gtk_app| {
           let window = Window::new(&gtk_app);
            gtk_app.add_window(&window.widget);
            window.widget.present();
            window.widget.show();
            app.window.replace(Rc::new(Some(window)));
        }));
    }

    fn setup_css(&self) {
        let p = gtk::CssProvider::new();
        gtk::CssProvider::load_from_resource(&p, "/org/gnome/Tour/style.css");
        if let Some(screen) = gdk::Screen::get_default() {
            gtk::StyleContext::add_provider_for_screen(&screen, &p, 500);
        }
    }

    pub fn run(&self) {
        info!("GNOME Tour{} ({})", config::NAME_SUFFIX, config::APP_ID);
        info!("Version: {} ({})", config::VERSION, config::PROFILE);
        info!("Datadir: {}", config::PKGDATADIR);

        let args: Vec<String> = env::args().collect();
        self.app.run(&args);
    }
}
