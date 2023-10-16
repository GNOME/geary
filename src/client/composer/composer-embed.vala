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
 * Widget.PresentationMode.INLINE} or {@link
 * Widget.PresentationMode.INLINE_COMPACT} mode.
 */
public class Composer.Embed : Gtk.EventBox, Container {

    private const int MIN_EDITOR_HEIGHT = 200;


    static construct {
        set_css_name("geary-composer-embed");
    }


    /** {@inheritDoc} */
    public Gtk.ApplicationWindow? top_window {
        get { return get_toplevel() as Gtk.ApplicationWindow; }
    }

    /** The email this composer was originally a reply to. */
    public Geary.Email referred { get; private set; }

    /** {@inheritDoc} */
    internal Widget composer { get; set; }

    private Gtk.ScrolledWindow outer_scroller;


    /** Emitted when the container is closed. */
    public signal void vanished();


    public Embed(Geary.Email referred,
                 Widget composer,
                 Gtk.ScrolledWindow outer_scroller) {
        this.referred = referred;
        this.composer = composer;
        this.composer.embed_header();

        Widget.PresentationMode mode = INLINE_COMPACT;
        if (composer.context_type == FORWARD ||
            composer.has_multiple_from_addresses) {
            mode = INLINE;
        }
        composer.set_mode(mode);

        this.outer_scroller = outer_scroller;

        get_style_context().add_class("geary-composer-embed");
        this.halign = Gtk.Align.FILL;
        this.vexpand = true;
        this.vexpand_set = true;

        add(composer);
        realize.connect(on_realize);
        show();
    }

    /** {@inheritDoc} */
    public void close() {
        disable_scroll_reroute(this);
        vanished();

        this.composer.free_header();
        remove(this.composer);
        destroy();
    }
}
