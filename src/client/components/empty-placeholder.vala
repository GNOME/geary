/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A placeholder image and message for empty views.
 */
[GtkTemplate (ui = "/org/gnome/Geary/empty-placeholder.ui")]
public class EmptyPlaceholder : Gtk.Grid {

    public string image_name {
        owned get { return this.placeholder_image.icon_name; }
        set { this.placeholder_image.icon_name = value; }
    }

    public string title {
        get { return this.title_label.get_text(); }
        set { this.title_label.set_text(value); }
    }

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
