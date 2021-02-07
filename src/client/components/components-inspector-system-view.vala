/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A view that displays system and library information.
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-inspector-system-view.ui")]
public class Components.InspectorSystemView : Gtk.Grid {



    private class DetailRow : Gtk.ListBoxRow {


        private Gtk.Grid layout {
            get; private set; default = new Gtk.Grid();
        }

        private Gtk.Label label {
            get; private set; default = new Gtk.Label("");
        }

        private Gtk.Label value {
            get; private set; default = new Gtk.Label("");
        }


        public DetailRow(string label, string value) {
            get_style_context().add_class("geary-labelled-row");

            this.label.halign = Gtk.Align.START;
            this.label.valign = Gtk.Align.CENTER;
            this.label.set_text(label);
            this.label.show();

            this.value.halign = Gtk.Align.END;
            this.value.hexpand = true;
            this.value.valign = Gtk.Align.CENTER;
            this.value.xalign = 1.0f;
            this.value.set_text(value);
            this.value.show();

            this.layout.orientation = Gtk.Orientation.HORIZONTAL;
            this.layout.add(this.label);
            this.layout.add(this.value);
            this.layout.show();
            add(this.layout);

            this.activatable = false;
            show();
        }

    }


    [GtkChild] private unowned Gtk.ListBox system_list;

    private Gee.Collection<Application.Client.RuntimeDetail?> details;


    public InspectorSystemView(Application.Client application) {
        this.details = application.get_runtime_information();
        foreach (Application.Client.RuntimeDetail? detail in this.details) {
            this.system_list.add(
                new DetailRow("%s:".printf(detail.name), detail.value)
            );
        }
    }

    public void save(GLib.DataOutputStream out,
                     Inspector.TextFormat format,
                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        string line_sep = format.get_line_separator();
        foreach (Application.Client.RuntimeDetail? detail in this.details) {
            out.put_string(detail.name);
            out.put_string(": ");
            out.put_string(detail.value);
            out.put_string(line_sep);
        }
    }

}
