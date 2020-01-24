use crate::config;
use crate::widgets::ApplicationWindow;
use gio::prelude::*;
use gtk::prelude::*;
use once_cell::unsync::OnceCell;
use std::env;

use gio::subclass::application::ApplicationImplExt;
use gio::ApplicationFlags;
use glib::subclass;
use glib::subclass::prelude::*;
use glib::translate::*;
use gtk::subclass::prelude::*;

#[derive(Debug)]
pub struct ApplicationPrivate {
    window: OnceCell<ApplicationWindow>,
}

impl ObjectSubclass for ApplicationPrivate {
    const NAME: &'static str = "ApplicationPrivate";
    type ParentType = gtk::Application;
    type Instance = subclass::simple::InstanceStruct<Self>;
    type Class = subclass::simple::ClassStruct<Self>;

    glib_object_subclass!();

    fn new() -> Self {
        Self { window: OnceCell::new() }
    }
}

impl ObjectImpl for ApplicationPrivate {
    glib_object_impl!();
}

impl ApplicationImpl for ApplicationPrivate {
    fn activate(&self, app: &gio::Application) {
        let app = app.downcast_ref::<gtk::Application>().unwrap();
        let priv_ = ApplicationPrivate::from_instance(app);
        let window = priv_.window.get().expect("Should always be initiliazed in gio_application_startup");
        window.show();
        window.present();
    }

    fn startup(&self, app: &gio::Application) {
        self.parent_startup(app);

        let p = gtk::CssProvider::new();
        gtk::CssProvider::load_from_resource(&p, "/org/gnome/Tour/style.css");
        if let Some(display) = gdk::Display::get_default() {
            gtk::StyleContext::add_provider_for_display(&display, &p, 500);
        }
        let app = ObjectSubclass::get_instance(self).downcast::<Application>().unwrap();
        let priv_ = ApplicationPrivate::from_instance(&app);
        let window = ApplicationWindow::new(&app);

        priv_.window.set(window).expect("Failed to initialize application window");
    }
}

impl GtkApplicationImpl for ApplicationPrivate {}

glib_wrapper! {
    pub struct Application(
        Object<subclass::simple::InstanceStruct<ApplicationPrivate>,
        subclass::simple::ClassStruct<ApplicationPrivate>,
        ApplicationClass>)
        @extends gio::Application, gtk::Application;

    match fn {
        get_type => || ApplicationPrivate::get_type().to_glib(),
    }
}

impl Application {
    pub fn run() {
        info!("GNOME Tour{} ({})", config::NAME_SUFFIX, config::APP_ID);
        info!("Version: {} ({})", config::VERSION, config::PROFILE);
        info!("Datadir: {}", config::PKGDATADIR);
        let app = glib::Object::new(Self::static_type(), &[("application-id", &config::APP_ID), ("flags", &ApplicationFlags::empty())])
            .expect("Failed to create SimpleApp")
            .downcast::<Application>()
            .expect("Created simpleapp is of wrong type");

        let args: Vec<String> = env::args().collect();
        ApplicationExtManual::run(&app, &args);
    }
}
