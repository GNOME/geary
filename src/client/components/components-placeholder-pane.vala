/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A placeholder image and message for empty views.
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-placeholder-pane.ui")]
public class Components.PlaceholderPane : Gtk.Grid {

    /** The icon name of the pane's image. */
    public string icon_name {
        owned get { return this.placeholder_image.icon_name; }
        set { this.placeholder_image.icon_name = value; }
    }

    /** The text of the pane's title label. */
    public string title {
        get { return this.title_label.get_text(); }
        set { this.title_label.set_text(value); }
    }

    /** The text of the pane's sub-title label. */
    public string subtitle {
        get { return this.subtitle_label.get_text(); }
        set { this.subtitle_label.set_text(value); }
    }

    [GtkChild]
    private Gtk.Image placeholder_image;

    [GtkChild]
    private Gtk.Label title_label;

    [GtkChild]
    private Gtk.Label subtitle_label;

}
