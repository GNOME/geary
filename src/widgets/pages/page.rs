pub trait Pageable {
    fn get_widget(&self) -> gtk::Widget;
    fn get_title(&self) -> String;
    fn get_head(&self) -> String;
    fn get_body(&self) -> String;
}
