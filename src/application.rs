use crate::config;
use crate::utils;
use crate::widgets::Window;
use gio::prelude::*;
use gtk::prelude::*;
use std::env;
use std::rc::Rc;

pub struct Application {
    app: gtk::Application,
    window: Rc<Window>,
}

impl Application {
    pub fn new() -> Self {
        let app = gtk::Application::new(Some(config::APP_ID), gio::ApplicationFlags::FLAGS_NONE).unwrap();
        let window = Rc::new(Window::new(&app));

        let application = Self { app, window };

        application.setup_gactions();
        application.setup_signals();
        application.setup_css();
        application
    }

    fn setup_gactions(&self) {
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
            clone!(@strong self.window as window => move |_, _| {
                window.start_tour();
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
            clone!(@strong self.window as window => move |_, _| {
                window.next_page();
            }),
        );
        utils::action(
            &self.app,
            "previous-page",
            clone!(@strong self.window as window => move |_, _| {
                window.previous_page();
            }),
        );
        self.app.set_accels_for_action("app.quit", &["<primary>q"]);
    }

    fn setup_signals(&self) {
        self.app.connect_activate(clone!(@weak self.window.widget as window => move |app| {
            app.add_window(&window);
            window.present();
        }));
    }

    fn setup_css(&self) {
        let p = gtk::CssProvider::new();
        gtk::CssProvider::load_from_resource(&p, "/org/gnome/Tour/style.css");
        if let Some(display) = gdk::Display::get_default() {
            gtk::StyleContext::add_provider_for_display(&display, &p, 500);
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
