use gtk::prelude::*;
use std::cell::RefCell;
use std::convert::TryInto;

use super::pages::ImagePageWidget;

pub struct PaginatorWidget {
    pub widget: gtk::Stack,
    pages: Vec<ImagePageWidget>,
    current_page: RefCell<i32>,
}

impl PaginatorWidget {
    pub fn new() -> Self {
        let widget = gtk::Stack::new();

        let paginator = Self {
            widget,
            pages: Vec::new(),
            current_page: RefCell::new(1),
        };
        paginator.init();
        paginator
    }

    pub fn next(&self) {
        let next_page = self.current_page.borrow().clone() + 1;
        self.go_to(next_page);
    }

    pub fn previous(&self) {
        let previous_page = self.current_page.borrow().clone() - 1;
        self.go_to(previous_page);
    }

    pub fn add_page(&mut self, page: ImagePageWidget) {
        let page_nr = self.pages.len() + 1;
        let page_name = format!("page-{}", page_nr);

        self.widget.add_named(&page.widget, &page_name);
        self.pages.push(page);
    }

    fn init(&self) {
        self.widget.set_transition_type(gtk::StackTransitionType::SlideLeftRight);
        self.widget.set_transition_duration(300);
    }

    fn go_to(&self, page_nr: i32) {
        let page_name = format!("page-{}", page_nr);
        let total_pages: i32 = self.pages.len().try_into().unwrap_or(0);

        if page_nr <= total_pages && self.widget.get_child_by_name(&page_name).is_some() {
            self.current_page.replace(page_nr);
            self.widget.set_visible_child_name(&page_name);
        }
    }
}
