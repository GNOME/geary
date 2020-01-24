pub fn action<T, F>(thing: &T, name: &str, action: F)
where
    T: gio::ActionMapExt,
    for<'r, 's> F: Fn(&'r gio::SimpleAction, Option<&glib::Variant>) + 'static,
{
    // Create a stateless, parameterless action
    let act = gio::SimpleAction::new(name, None);
    // Connect the handler
    act.connect_activate(action);
    // Add it to the map
    thing.add_action(&act);
}
