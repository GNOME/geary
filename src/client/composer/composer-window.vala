/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A ComposerWindow is a ComposerContainer that is used to compose mails in a separate window
 * (i.e. detached) of its own.
 */
public class ComposerWindow : Gtk.ApplicationWindow, ComposerContainer {


    private const string DEFAULT_TITLE = _("New Message");


    public Gtk.ApplicationWindow top_window {
        get { return this; }
    }

    internal ComposerWidget composer { get; set; }

    protected Gee.MultiMap<string, string>? old_accelerators { get; set; }

    private bool closing = false;

    public ComposerWindow(ComposerWidget composer) {
        Object(type: Gtk.WindowType.TOPLEVEL);
        this.composer = composer;

        // Make sure it gets added to the GtkApplication, to get the window-specific
        // composer actions to work properly.
        GearyApplication.instance.add_window(this);

        // XXX Bug 764622
        set_property("name", "GearyComposerWindow");

        add(this.composer);

        if (composer.config.desktop_environment == Configuration.DesktopEnvironment.UNITY) {
            composer.embed_header();
        } else {
            composer.header.show_close_button = true;
            composer.free_header();
            set_titlebar(this.composer.header);
        }

        composer.subject_changed.connect(() => { update_title(); } );
        update_title();

        show();
        set_position(Gtk.WindowPosition.CENTER);
    }

    public override void show() {
        Gdk.Display? display = Gdk.Display.get_default();
        if (display != null) {
            Gdk.Monitor? monitor = display.get_primary_monitor();
            if (monitor == null) {
                monitor = display.get_monitor_at_point(1, 1);
            }
            int[] size = GearyApplication.instance.config.composer_window_size;
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
                    GearyApplication.instance.config.composer_window_size = {
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

    public void close_container() {
        this.closing = true;
        destroy();
    }

    public override bool delete_event(Gdk.EventAny event) {
        return !(this.closing ||
            ((ComposerWidget) get_child()).should_close() == ComposerWidget.CloseStatus.DO_CLOSE);
    }

    public void vanish() {
        hide();
    }

    public void remove_composer() {
        warning("Detached composer received remove");
    }

    private void update_title() {
        string subject = this.composer.subject.strip();
        if (Geary.String.is_empty_or_whitespace(subject)) {
            subject = DEFAULT_TITLE;
        }

        switch (this.composer.config.desktop_environment) {
        case Configuration.DesktopEnvironment.UNITY:
            this.title = subject;
            break;

        default:
            this.composer.header.title = subject;
            break;
        }
    }

}
