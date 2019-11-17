/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A container for full-height paned composers in the main window.
 */
public class Composer.Box : Gtk.Frame, Container {

    /** {@inheritDoc} */
    public Gtk.ApplicationWindow? top_window {
        get { return get_toplevel() as Gtk.ApplicationWindow; }
    }

    /** {@inheritDoc} */
    internal Widget composer { get; set; }

    private MainToolbar main_toolbar { get; private set; }


    /** Emitted when the container is closed. */
    public signal void vanished();


    public Box(Widget composer, MainToolbar main_toolbar) {
        this.composer = composer;

        this.main_toolbar = main_toolbar;
        this.main_toolbar.set_conversation_header(composer.header);

        get_style_context().add_class("geary-composer-box");
        this.halign = Gtk.Align.FILL;
        this.vexpand = true;
        this.vexpand_set = true;

        add(this.composer);
        show();
    }

    /** {@inheritDoc} */
    public void close() {
        vanished();

        this.main_toolbar.remove_conversation_header(composer.header);
        remove(this.composer);
        destroy();
    }

}
