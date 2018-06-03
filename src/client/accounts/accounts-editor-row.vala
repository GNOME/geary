/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */


internal class Accounts.EditorRow : Gtk.ListBoxRow {


    protected Gtk.Grid layout { get; private set; default = new Gtk.Grid(); }


    public EditorRow() {
        get_style_context().add_class("geary-settings");

        this.layout.orientation = Gtk.Orientation.HORIZONTAL;
        this.layout.show();
        add(this.layout);

        this.show();
    }

}


internal class Accounts.LabelledEditorRow : EditorRow {


    protected Gtk.Label label { get; private set; default = new Gtk.Label(""); }


    public LabelledEditorRow(string label) {
        this.label.set_text(label);
        this.label.set_hexpand(true);
        this.label.halign = Gtk.Align.START;
        this.label.show();

        this.layout.add(this.label);
    }

    public void set_dim_label(bool is_dim) {
        if (is_dim) {
            this.label.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
        } else {
            this.label.get_style_context().remove_class(Gtk.STYLE_CLASS_DIM_LABEL);
        }
    }

}


internal class Accounts.AddRow : EditorRow {


    public AddRow() {
        Gtk.Image add_icon = new Gtk.Image.from_icon_name(
            "list-add-symbolic", Gtk.IconSize.BUTTON
        );
        add_icon.set_hexpand(true);
        add_icon.show();

        this.layout.add(add_icon);
    }


}
