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
        Object(application: application);
        this.composer = composer;
        this.composer.set_mode(DETACHED);

        // Create a new group for the window so attachment file
        // choosers do not block other main windows or composers.
        var group = new Gtk.WindowGroup();
        group.add_window(this);

        // XXX Bug 764622
        set_property("name", "GearyComposerWindow");

        this.child = this.composer;

        this.composer.update_window_title();
        if (application.config.desktop_environment == UNITY) {
            composer.embed_header();
        } else {
            set_titlebar(this.composer.header.headerbar);
        }

        Gtk.EventControllerFocus focus_controller = new Gtk.EventControllerFocus();
        focus_controller.enter.connect((controller) => {
            application.controller.window_focus_in();
        });
        focus_controller.leave.connect((controller) => {
            application.controller.window_focus_out();
        });
        ((Gtk.Widget) this).add_controller(focus_controller);
    }

    /** {@inheritDoc} */
    public new void close() {
        this.child = null;
    }

    public override void show() {
        Gdk.Display? display = Gdk.Display.get_default();
        if (display != null) {
            Gdk.Monitor? monitor = display.get_monitor_at_surface(get_surface());
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
        if (!this.maximized) {
            Gdk.Display? display = get_display();
            Gdk.Surface? surface = get_surface();
            if (display != null && surface != null) {
                Gdk.Monitor monitor = display.get_monitor_at_surface(surface);

                // Only store if the values are reasonable-looking.
                if (this.default_width > 0 && this.default_width <= monitor.geometry.width &&
                    this.default_height > 0 && this.default_height <= monitor.geometry.height) {
                    this.application.config.set_composer_window_size({
                            this.default_width, this.default_height
                        });
                }
            }
        }
    }

    public override bool close_request() {
        save_window_geometry();

        // Use the child instead of the `composer` property so we
        // don't check with the composer if it has already been
        // removed from the container.
        Widget? child = get_child() as Widget;
        bool ret = Gdk.EVENT_PROPAGATE;
        // XXX GTK4 - This is now an async method, I'm not sure we can still stop htis?
        // if (child != null &&
        //     child.conditional_close(true) == CANCELLED) {
        //     ret = Gdk.EVENT_STOP;
        // }
        return ret;
    }

}
