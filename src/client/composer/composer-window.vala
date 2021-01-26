/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A container detached composers, i.e. in their own separate window.
 *
 * Adding a composer to this container places it in {@link
 * Widget.PresentationMode.DETACHED} mode.
 */
public class Composer.Window : Gtk.ApplicationWindow, Container {

    static construct {
        set_css_name("geary-composer-box");
    }


    /** {@inheritDoc} */
    public Gtk.ApplicationWindow? top_window {
        get { return this; }
    }

    /** {@inheritDoc} */
    public new Application.Client application {
        get { return (Application.Client) base.get_application(); }
        set { base.set_application(value); }
    }

    /** {@inheritDoc} */
    internal Widget composer { get; set; }


    public Window(Widget composer, Application.Client application) {
        Object(application: application, type: Gtk.WindowType.TOPLEVEL);
        this.composer = composer;
        this.composer.set_mode(DETACHED);

        // Create a new group for the window so attachment file
        // choosers do not block other main windows or composers.
        var group = new Gtk.WindowGroup();
        group.add_window(this);

        // XXX Bug 764622
        set_property("name", "GearyComposerWindow");

        add(this.composer);

        this.composer.update_window_title();
        if (application.config.desktop_environment == UNITY) {
            composer.embed_header();
        } else {
            set_titlebar(this.composer.header);
        }

        this.focus_in_event.connect((w, e) => {
            application.controller.window_focus_in();
            return false;
        });
        this.focus_out_event.connect((w, e) => {
            application.controller.window_focus_out();
            return false;
        });

        show();
        set_position(Gtk.WindowPosition.CENTER);
    }

    /** {@inheritDoc} */
    public new void close() {
        this.composer.free_header();
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
            int[] size = this.application.config.get_composer_window_size();
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
                    this.application.config.set_composer_window_size({
                            width, height
                        });
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
        // Use the child instead of the `composer` property so we
        // don't check with the composer if it has already been
        // removed from the container.
        Widget? child = get_child() as Widget;
        bool ret = Gdk.EVENT_PROPAGATE;
        if (child != null &&
            child.conditional_close(true) == CANCELLED) {
            ret = Gdk.EVENT_STOP;
        }
        return ret;
    }

}
