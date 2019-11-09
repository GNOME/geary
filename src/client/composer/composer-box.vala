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


    public Box(Widget composer) {
        this.composer = composer;
        this.composer.free_header();

        this.main_toolbar = GearyApplication.instance.controller.main_window.main_toolbar;

        get_style_context().add_class("geary-composer-box");
        this.halign = Gtk.Align.FILL;
        this.vexpand = true;
        this.vexpand_set = true;

        add(this.composer);
        this.main_toolbar.set_conversation_header(composer.header);
        show();
    }

    /** {@inheritDoc} */
    public void close() {
        this.main_toolbar.remove_conversation_header(composer.header);
        vanished();

        remove(this.composer);
        destroy();
    }

}
