use anyhow::Result;
use gettextrs::gettext;
use gtk::prelude::*;
use std::cell::RefCell;
use std::rc::Rc;

use super::pages::Pageable;
use libhandy::prelude::{CarouselExt, HeaderBarExt};

pub struct PaginatorWidget {
    pub widget: gtk::Box,
    carousel: libhandy::Carousel,
    headerbar: libhandy::HeaderBar,
    pages: RefCell<Vec<Box<dyn Pageable>>>,
    current_page: RefCell<u32>,
    next_btn: gtk::Button,
    close_btn: gtk::Button,
}

impl PaginatorWidget {
    pub fn new() -> Rc<Self> {
        let widget = gtk::Box::new(gtk::Orientation::Vertical, 0);

        let paginator = Rc::new(Self {
            widget,
            carousel: libhandy::Carousel::new(),
            headerbar: libhandy::HeaderBar::new(),
            next_btn: gtk::Button::with_label(&gettext("_Next")),
            close_btn: gtk::Button::with_label(&gettext("_Close")),
            pages: RefCell::new(Vec::new()),
            current_page: RefCell::new(0),
        });
        paginator.init(paginator.clone());
        paginator
    }

    pub fn next(&self) -> Result<()> {
        let p = *self.current_page.borrow() + 1;
        if p == self.carousel.get_n_pages() {
            anyhow::bail!("Already at the latest page");
        }
        self.set_page(p);
        Ok(())
    }

    pub fn previous(&self) -> Result<()> {
        let p = *self.current_page.borrow();
        if p == 0 {
            anyhow::bail!("Already at the first page");
        }
        self.set_page(p - 1);
        Ok(())
    }

    pub fn add_page(&self, page: Box<dyn Pageable>) {
        let page_nr = self.pages.borrow().len();
        self.carousel.insert(&page.get_widget(), page_nr as i32);
        self.pages.borrow_mut().push(page);
    }

    fn init(&self, p: Rc<Self>) {
        self.carousel.set_property_expand(true);
        self.carousel.set_animation_duration(300);

        self.carousel.connect_property_position_notify(clone!(@weak p => move |carousel| {
            let n_pages = carousel.get_n_pages() as f64;
            let position = carousel.get_position();
            let opacity = (position - n_pages + 2_f64).max(0_f64);

            p.close_btn.set_opacity(opacity);
            p.close_btn.set_visible(opacity > 0_f64);

            let page_nr = position.round() as u32;
            let pages = &p.pages.borrow();
            let page = pages.get(page_nr as usize).unwrap();

            p.headerbar.set_title(Some(&page.get_title()));
            p.current_page.replace(page_nr);
        }));

        let previous_btn = gtk::Button::with_label(&gettext("_Previous"));
        previous_btn.set_use_underline(true);
        previous_btn.set_action_name(Some("app.previous-page"));

        let btn_size_group = gtk::SizeGroup::new(gtk::SizeGroupMode::Horizontal);
        btn_size_group.add_widget(&previous_btn);
        btn_size_group.add_widget(&self.next_btn);
        btn_size_group.add_widget(&self.close_btn);

        self.next_btn.get_style_context().add_class("suggested-action");
        self.next_btn.set_use_underline(true);
        self.next_btn.set_action_name(Some("app.next-page"));

        self.close_btn.get_style_context().add_class("suggested-action");
        self.close_btn.set_use_underline(true);
        self.close_btn.set_action_name(Some("app.next-page"));

        let next_overlay = gtk::Overlay::new();
        next_overlay.add(&self.next_btn);
        next_overlay.add_overlay(&self.close_btn);

        self.headerbar.pack_start(&previous_btn);
        self.headerbar.pack_end(&next_overlay);
        self.headerbar.set_show_close_button(false);

        self.widget.add(&self.headerbar);
        self.widget.add(&self.carousel);
    }

    pub fn set_page(&self, page_nr: u32) {
        if page_nr < self.carousel.get_n_pages() {
            let pages = &self.pages.borrow();
            let page = pages.get(page_nr as usize).unwrap();
            self.carousel.scroll_to(&page.get_widget());
        }
    }
}
