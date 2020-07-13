pub trait Pageable {
    fn get_widget(&self) -> gtk::Widget;
    fn get_title(&self) -> String;
}
