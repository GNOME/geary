/*
 * Copyright 2025 Niels De Graef <nielsdegraef@gmail.com>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Groups several validators together, allowing to show an aggregate result.
 */
public class Components.ValidatorGroup : GLib.Object, GLib.ListModel, Gtk.Buildable {

    private GenericArray<Validator> validators = new GenericArray<Validator>();

    /** Fired when the relevant validator has changed */
    public signal void changed(Validator validator);

    /** Fired when the relevant validator has emitted the activated signal */
    public signal void activated(Validator validator);

    public void add_validator(Validator validator) {
        validator.changed.connect(on_validator_changed);
        validator.activated.connect(on_validator_activated);
        this.validators.add(validator);
    }

    private void on_validator_changed(Validator validator) {
        this.changed(validator);
    }

    private void on_validator_activated(Validator validator) {
        this.activated(validator);
    }

    public bool is_valid() {
        foreach (unowned var validator in this.validators) {
            if (validator.is_valid)
                return false;
        }

        return true;
    }

    // GListModel implementation

    public GLib.Type get_item_type() {
        return typeof(Components.Validator);
    }

    public uint get_n_items() {
        return this.validators.length;
    }

    public GLib.Object? get_item(uint index) {
        if (index >= this.validators.length)
            return null;
        return this.validators[index];
    }

    // GtkBuildable implementation

    public void add_child(Gtk.Builder builder, Object child, string? type) {
        unowned var validator = child as Validator;
        if (validator == null) {
            critical("Can't add child %p to ValidatorGroup, expected Validator instance", validator);
            return;
        }

        add_validator(validator);
    }

    private string id;
    public void set_id(string id) {
        this.id = id;
    }
    public unowned string get_id() {
        return this.id;
    }

    // We don't need any of these, but Vala requires us to implement them
    public void custom_finished(Gtk.Builder builder, GLib.Object? child, string tagname, void* data) {}
    public void custom_tag_end(Gtk.Builder builder, GLib.Object? child, string tagname, void* data) {}
    public bool custom_tag_start(Gtk.Builder builder, GLib.Object? child, string tagname, out Gtk.BuildableParser parser, out void* data) {
        return false;
    }
    public unowned GLib.Object get_internal_child(Gtk.Builder builder, string childname) {
        return null;
    }
    public void parser_finished(Gtk.Builder builder) {}
    public void set_buildable_property(Gtk.Builder builder, string name, GLib.Value value) {}
}
