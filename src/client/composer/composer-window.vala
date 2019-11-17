/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A container detached composers, i.e. in their own separate window.
 */
public class Composer.Window : Gtk.ApplicationWindow, Container {


    private const string DEFAULT_TITLE = _("New Message");


    /** {@inheritDoc} */
    public Gtk.ApplicationWindow? top_window {
        get { return this; }
    }

    /** {@inheritDoc} */
    public new GearyApplication? application {
        get { return base.get_application() as GearyApplication; }
        set { base.set_application(value); }
    }

    /** {@inheritDoc} */
    internal Widget composer { get; set; }


    public Window(Widget composer, GearyApplication application) {
        Object(application: application, type: Gtk.WindowType.TOPLEVEL);
        this.composer = composer;
        this.composer.header.detached();

        // XXX Bug 764622
        set_property("name", "GearyComposerWindow");

        add(this.composer);

        if (application.config.desktop_environment == UNITY) {
            composer.embed_header();
        } else {
            composer.header.show_close_button = true;
            composer.free_header();
            set_titlebar(this.composer.header);
        }

        composer.notify["subject"].connect(() => { update_title(); } );
        update_title();

        show();
        set_position(Gtk.WindowPosition.CENTER);
    }

    /** {@inheritDoc} */
    public new void close() {
        remove(this.composer);
        destroy();
    }

    public override void show() {
        Gdk.Display? display = Gdk.Display.get_default();
        if (display != null) {
            Gdk.Monitor? monitor = display.get_primary_monitor();
            if (monitor == null) {
                monitor = display.get_monitor_at_point(1, 1);
            }
            int[] size = this.application.config.composer_window_size;
            //check if stored values are reasonable
            if (monitor != null &&
                size[0] >= 0 && size[0] <= monitor.geometry.width &&
                size[1] >= 0 && size[1] <= monitor.geometry.height) {
                set_default_size(size[0], size[1]);
            } else {
                set_default_size(680, 600);
            }
        }

        base.show();
    }

    private void save_window_geometry () {
        if (!this.is_maximized) {
            Gdk.Display? display = get_display();
            Gdk.Window? window = get_window();
            if (display != null && window != null) {
                Gdk.Monitor monitor = display.get_monitor_at_window(window);

                int width = 0;
                int height = 0;
                get_size(out width, out height);

                // Only store if the values are reasonable-looking.
                if (width > 0 && width <= monitor.geometry.width &&
                    height > 0 && height <= monitor.geometry.height) {
                    this.application.config.composer_window_size = {
                        width, height
                    };
                }
            }
        }
    }

    // Fired on window resize. Save window size for the next start.
    public override void size_allocate(Gtk.Allocation allocation) {
        base.size_allocate(allocation);

        this.save_window_geometry();
    }

    public override bool delete_event(Gdk.EventAny event) {
        bool ret = Gdk.EVENT_PROPAGATE;
        Widget? composer = get_child() as Widget;
        if (composer != null && composer.should_close() == CANCEL_CLOSE) {
            ret = Gdk.EVENT_STOP;
        }
        return ret;
    }

    private void update_title() {
        string subject = this.composer.subject.strip();
        if (Geary.String.is_empty_or_whitespace(subject)) {
            subject = DEFAULT_TITLE;
        }

        switch (this.application.config.desktop_environment) {
        case UNITY:
            this.title = subject;
            break;

        default:
            this.composer.header.title = subject;
            break;
        }
    }

}
