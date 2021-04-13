/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A container for full-height paned composers in the main window.
 *
 * Adding a composer to this container places it in {@link
 * Widget.PresentationMode.PANED} mode.
 */
public class Composer.Box : Gtk.Frame, Container {

    static construct {
        set_css_name("geary-composer-box");
    }


    /** {@inheritDoc} */
    public Gtk.ApplicationWindow? top_window {
        get { return get_toplevel() as Gtk.ApplicationWindow; }
    }

    /** {@inheritDoc} */
    internal Widget composer { get; set; }

    private Components.MainToolbar main_toolbar { get; private set; }


    /** Emitted when the container is closed. */
    public signal void vanished();


    public Box(Widget composer, Components.MainToolbar main_toolbar) {
        this.composer = composer;
        this.composer.set_mode(PANED);

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
