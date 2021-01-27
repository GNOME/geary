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

    private void on_realize() {
        reroute_scroll_handling(this);
    }

    private void reroute_scroll_handling(Gtk.Widget widget) {
        widget.add_events(Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK);
        widget.scroll_event.connect(on_inner_scroll_event);
        Gtk.Container? container = widget as Gtk.Container;
        if (container != null) {
            foreach (Gtk.Widget child in container.get_children())
                reroute_scroll_handling(child);
        }
    }

    private void disable_scroll_reroute(Gtk.Widget widget) {
        widget.scroll_event.disconnect(on_inner_scroll_event);
        Gtk.Container? container = widget as Gtk.Container;
        if (container != null) {
            foreach (Gtk.Widget child in container.get_children())
                disable_scroll_reroute(child);
        }
    }

    // This method intercepts scroll events destined for the embedded
    // composer and diverts them them to the conversation listbox's
    // outer scrolled window or the composer's editor as appropriate.
    //
    // The aim is to let the user increase the height of the composer
    // via scrolling when it it smaller than the current scrolled
    // window, scroll through the conversation itself, and also scroll
    // the composer's editor, in a reasonably natural way.
    private bool on_inner_scroll_event(Gdk.EventScroll event) {
        // Bugs & improvements:
        //
        // - Clamp top of embedded window to top/bottom of viewport a
        //   bit better, sometimes it will sit a few pixels below the
        //   toolbar will be or be half obscured by the top of the
        //   viewport, etc
        // - Maybe let the user shrink the size of the composer down
        //   when scrolling up?
        // - When window size changes, need to adjust size of composer
        //   window, although maybe that might be taken care of by
        //   allowing the user to scroll to shrink the size of the
        //   window?

        bool ret = Gdk.EVENT_STOP;
        if (event.direction == Gdk.ScrollDirection.SMOOTH &&
            event.delta_y != 0.0) {
            // Scrolling vertically
            Gtk.Adjustment adj  = this.outer_scroller.vadjustment;
            Gtk.Allocation alloc;
            get_allocation(out alloc);

            // Scroll unit calc taken from
            // gtk_scrolled_window_scroll_event
            double scroll_unit = Math.pow(adj.page_size, 2.0 / 3.0);
            double scroll_delta = event.delta_y * scroll_unit;
            double initial_value = adj.value;

            if (event.delta_y > 0.0) {
                // Scrolling down
                if (alloc.y > adj.value) {
                    // This embed isn't against the top of the visible
                    // area, so scroll the outer. Clamp the scroll
                    // delta to bring it to the top at most.
                    event.delta_y = (
                        Math.fmin(scroll_delta, alloc.y - adj.value) / scroll_unit
                    );
                    this.outer_scroller.scroll_event(event);
                }
                double remainder_delta = scroll_delta - (adj.value - initial_value);

                if (remainder_delta > 0.0001) {
                    // Outer scroller didn't use the complete delta,
                    // so work out what to do with the remainder.

                    var body = this.composer.editor.body;
                    int editor_height = body.get_allocated_height();
                    int editor_preferred = body.preferred_height;
                    int scrolled_height = body.get_allocated_height();

                    if (alloc.height < scrolled_height &&
                        editor_height < editor_preferred) {
                        // The editor is smaller than allowed/preferred,
                        // so make it bigger
                        int editor_delta = (int) Math.round(remainder_delta);
                        if (editor_delta + alloc.height > scrolled_height) {
                            editor_delta = scrolled_height - alloc.height;
                        }
                        if (editor_delta + editor_height > editor_preferred) {
                            editor_delta = editor_preferred - editor_height;
                        }
                        remainder_delta -= editor_delta;
                        set_size_request(-1, get_allocated_height() + editor_delta);
                    } else {
                        // Still some scroll distance unused, so let the
                        // editor have at it.
                        event.delta_y = (remainder_delta / scroll_unit);
                        ret = Gdk.EVENT_PROPAGATE;
                    }
                }
            } else if (event.delta_y < 0.0) {
                // Scrolling up
                double alloc_bottom = alloc.y + alloc.height;
                double adj_bottom = adj.value + adj.page_size;
                if (alloc_bottom < adj_bottom) {
                    // This embed isn't against the bottom of the
                    // scrolled window, so scroll the scroll the
                    // outer. Clamp the scroll delta to bring it to
                    // the bottom at most.
                    event.delta_y = (
                        Math.fmax(scroll_delta, alloc_bottom - adj_bottom) / scroll_unit
                    );
                    this.outer_scroller.scroll_event(event);
                    double remainder_delta = scroll_delta - (adj.value - initial_value);
                    if (Math.fabs(remainder_delta) > 0.0001) {
                        event.delta_y = (remainder_delta / scroll_unit);
                        ret = Gdk.EVENT_PROPAGATE;
                    }
                } else {
                    ret = Gdk.EVENT_PROPAGATE;
                }
            }
        }
        return ret;
    }

}
