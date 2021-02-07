/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Displays the attachment parts for an email.
 *
 * This can be used in an editable or non-editable context, the UI
 * shown will differ slightly based on which is selected.
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-attachment-pane.ui")]
public class Components.AttachmentPane : Gtk.Grid {


    private const string GROUP_NAME = "cap";
    private const string ACTION_OPEN = "open";
    private const string ACTION_OPEN_SELECTED = "open-selected";
    private const string ACTION_REMOVE = "remove";
    private const string ACTION_REMOVE_SELECTED = "remove-selected";
    private const string ACTION_SAVE = "save";
    private const string ACTION_SAVE_ALL = "save-all";
    private const string ACTION_SAVE_SELECTED = "save-selected";
    private const string ACTION_SELECT_ALL = "select-all";

    private const ActionEntry[] action_entries = {
        { ACTION_OPEN, on_open, "s" },
        { ACTION_OPEN_SELECTED, on_open_selected },
        { ACTION_REMOVE, on_remove, "s" },
        { ACTION_REMOVE_SELECTED, on_remove_selected },
        { ACTION_SAVE, on_save, "s" },
        { ACTION_SAVE_ALL, on_save_all },
        { ACTION_SAVE_SELECTED, on_save_selected },
        { ACTION_SELECT_ALL, on_select_all },
    };


    // This exists purely to be able to set key bindings on it.
    private class FlowBox : Gtk.FlowBox {

        /** Keyboard action to open the currently selected attachments. */
        [Signal (action=true)]
        public signal void open_attachments();

        /** Keyboard action to save the currently selected attachments. */
        [Signal (action=true)]
        public signal void save_attachments();

        /** Keyboard action to remove the currently selected attachments. */
        [Signal (action=true)]
        public signal void remove_attachments();

    }

    // Displays an attachment's icon and details
    [GtkTemplate (ui = "/org/gnome/Geary/components-attachment-view.ui")]
    private class View : Gtk.Grid {


        private const int ATTACHMENT_ICON_SIZE = 32;
        private const int ATTACHMENT_PREVIEW_SIZE = 64;

        public Geary.Attachment attachment { get; private set; }

        [GtkChild] private unowned Gtk.Image icon;

        [GtkChild] private unowned Gtk.Label filename;

        [GtkChild] private unowned Gtk.Label description;

        private string gio_content_type;


        public View(Geary.Attachment attachment) {
            this.attachment = attachment;
            string mime_content_type = attachment.content_type.get_mime_type();
            this.gio_content_type = ContentType.from_mime_type(
                mime_content_type
            );

            string? file_name = attachment.content_filename;
            string file_desc = GLib.ContentType.get_description(gio_content_type);
            if (GLib.ContentType.is_unknown(gio_content_type)) {
                // Translators: This is the file type displayed for
                // attachments with unknown file types.
                file_desc = _("Unknown");
            }
            string file_size = Files.get_filesize_as_string(
                attachment.filesize
            );

            if (Geary.String.is_empty(file_name)) {
                // XXX Check for unknown types here and try to guess
                // using attachment data.
                file_name = file_desc;
                file_desc = file_size;
            } else {
                // Translators: The first argument will be a
                // description of the document type, the second will
                // be a human-friendly size string. For example:
                // Document (100.9MB)
                file_desc = _("%s (%s)".printf(file_desc, file_size));
            }
            this.filename.set_text(file_name);
            this.description.set_text(file_desc);
        }

        internal async void load_icon(GLib.Cancellable load_cancelled) {
            if (load_cancelled.is_cancelled()) {
                return;
            }

            Gdk.Pixbuf? pixbuf = null;

            // XXX We need to hook up to GtkWidget::style-set and
            // reload the icon when the theme changes.

            int window_scale = get_scale_factor();
            try {
                // If the file is an image, use it. Otherwise get the
                // icon for this mime_type.
                if (this.attachment.content_type.has_media_type("image")) {
                    // Get a thumbnail for the image.
                    // TODO Generate and save the thumbnail when
                    // extracting the attachments rather than when showing
                    // them in the viewer.
                    int preview_size = ATTACHMENT_PREVIEW_SIZE * window_scale;
                    GLib.InputStream stream = yield this.attachment.file.read_async(
                        Priority.DEFAULT,
                        load_cancelled
                    );
                    pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(
                        stream, preview_size, preview_size, true, load_cancelled
                    );
                    pixbuf = pixbuf.apply_embedded_orientation();
                } else {
                    // Load the icon for this mime type
                    GLib.Icon icon = GLib.ContentType.get_icon(
                        this.gio_content_type
                    );
                    Gtk.IconTheme theme = Gtk.IconTheme.get_default();
                    Gtk.IconLookupFlags flags = Gtk.IconLookupFlags.DIR_LTR;
                    if (get_direction() == Gtk.TextDirection.RTL) {
                        flags = Gtk.IconLookupFlags.DIR_RTL;
                    }
                    Gtk.IconInfo? icon_info = theme.lookup_by_gicon_for_scale(
                        icon, ATTACHMENT_ICON_SIZE, window_scale, flags
                    );
                    if (icon_info != null) {
                        pixbuf = yield icon_info.load_icon_async(load_cancelled);
                    }
                }
            } catch (GLib.Error error) {
                debug("Failed to load icon for attachment '%s': %s",
                      this.attachment.file.get_path(),
                      error.message);
            }

            if (pixbuf != null) {
                Cairo.Surface surface = Gdk.cairo_surface_create_from_pixbuf(
                    pixbuf, window_scale, get_window()
                );
                this.icon.set_from_surface(surface);
            }
        }

    }


    static construct {
        // Set up custom keybindings
        unowned Gtk.BindingSet bindings = Gtk.BindingSet.by_class(
            (ObjectClass) typeof(FlowBox).class_ref()
        );

        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.O, Gdk.ModifierType.CONTROL_MASK, "open-attachments", 0
        );

        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.S, Gdk.ModifierType.CONTROL_MASK, "save-attachments", 0
        );

        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.BackSpace, 0, "remove-attachments", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.Delete, 0, "remove-attachments", 0
        );
        Gtk.BindingEntry.add_signal(
            bindings, Gdk.Key.KP_Delete, 0, "remove-attachments", 0
        );
    }


    /** Determines if this pane's contents can be modified. */
    public bool edit_mode { get; private set; }

    private Gee.List<Geary.Attachment> attachments =
         new Gee.LinkedList<Geary.Attachment>();

    private Application.AttachmentManager manager;

    private GLib.SimpleActionGroup actions = new GLib.SimpleActionGroup();

    [GtkChild] private unowned Gtk.Grid attachments_container;

    [GtkChild] private unowned Gtk.Button save_button;

    [GtkChild] private unowned Gtk.Button remove_button;

    private FlowBox attachments_view;


    public AttachmentPane(bool edit_mode,
                          Application.AttachmentManager manager) {
        this.edit_mode = edit_mode;
        if (edit_mode) {
            save_button.hide();
        } else {
            remove_button.hide();
        }

        this.manager = manager;

        this.attachments_view = new FlowBox();
        this.attachments_view.open_attachments.connect(on_open_selected);
        this.attachments_view.remove_attachments.connect(on_remove_selected);
        this.attachments_view.save_attachments.connect(on_save_selected);
        this.attachments_view.child_activated.connect(on_child_activated);
        this.attachments_view.selected_children_changed.connect(on_selected_changed);
        this.attachments_view.button_press_event.connect(on_attachment_button_press);
		this.attachments_view.popup_menu.connect(on_attachment_popup_menu);
        this.attachments_view.activate_on_single_click = false;
        this.attachments_view.max_children_per_line = 3;
        this.attachments_view.column_spacing = 6;
        this.attachments_view.row_spacing = 6;
        this.attachments_view.selection_mode = Gtk.SelectionMode.MULTIPLE;
        this.attachments_view.hexpand = true;
        this.attachments_view.show();
        this.attachments_container.add(this.attachments_view);

        this.actions.add_action_entries(action_entries, this);
        insert_action_group(GROUP_NAME, this.actions);
    }

    public void add_attachment(Geary.Attachment attachment,
                               GLib.Cancellable? cancellable) {
        View view = new View(attachment);
        this.attachments_view.add(view);
        this.attachments.add(attachment);
        view.load_icon.begin(cancellable);

        update_actions();
    }

    public void open_attachment(Geary.Attachment attachment) {
        open_attachments(Geary.Collection.single(attachment));
    }

    public void save_attachment(Geary.Attachment attachment) {
        this.manager.save_attachment.begin(
            attachment,
            null,
            null // No cancellable for the moment, need UI for it
        );
    }

    public void remove_attachment(Geary.Attachment attachment) {
        this.attachments.remove(attachment);
        this.attachments_view.foreach(child => {
                Gtk.FlowBoxChild flow_child = (Gtk.FlowBoxChild) child;
                if (((View) flow_child.get_child()).attachment == attachment) {
                    this.attachments_view.remove(child);
                }
            });
    }

    public bool save_all() {
        bool ret = false;
        if (!this.attachments.is_empty) {
            var all = new Gee.ArrayList<Geary.Attachment>();
            all.add_all(this.attachments);
            this.manager.save_attachments.begin(
                all,
                null // No cancellable for the moment, need UI for it
            );
        }
        return ret;
    }

    private Geary.Attachment? get_attachment(GLib.Variant param) {
        Geary.Attachment? ret = null;
        string path = (string) param;
        foreach (var attachment in this.attachments) {
            if (attachment.file.get_path() == path) {
                ret = attachment;
                break;
            }
        }
        return ret;
    }

    private Gee.Collection<Geary.Attachment> get_selected_attachments() {
        var selected = new Gee.LinkedList<Geary.Attachment>();
        this.attachments_view.selected_foreach((box, child) => {
                selected.add(
                    ((View) child.get_child()).attachment
                );
            });
        return selected;
    }

    private bool open_selected() {
        bool ret = false;
        var selected = get_selected_attachments();
        if (!selected.is_empty) {
            open_attachments(selected);
            ret = true;
        }
        return ret;
    }

    private bool save_selected() {
        bool ret = false;
        var selected = get_selected_attachments();
        if (!this.edit_mode && !selected.is_empty) {
            this.manager.save_attachments.begin(
                selected,
                null // No cancellable for the moment, need UI for it
            );
            ret = true;
        }
        return ret;
    }

    private bool remove_selected() {
        bool ret = false;
        GLib.List<unowned Gtk.FlowBoxChild> children =
            this.attachments_view.get_selected_children();
        if (this.edit_mode && children.length() > 0) {
            children.foreach(child => {
                    this.attachments_view.remove(child);
                    this.attachments.remove(
                        ((View) child.get_child()).attachment
                    );
                });
            ret = true;
        }
        return ret;
    }

    private void update_actions() {
        uint len = this.attachments_view.get_selected_children().length();
        bool not_empty = len > 0;

        set_action_enabled(ACTION_OPEN_SELECTED, not_empty);
        set_action_enabled(ACTION_REMOVE_SELECTED, not_empty && this.edit_mode);
        set_action_enabled(ACTION_SAVE_SELECTED, not_empty && !this.edit_mode);
        set_action_enabled(ACTION_SELECT_ALL, len < this.attachments.size);
    }

    private void open_attachments(Gee.Collection<Geary.Attachment> attachments) {
        var main = this.get_toplevel() as Application.MainWindow;
        if (main != null) {
            Application.Client app = main.application;
            bool confirmed = true;
            if (app.config.ask_open_attachment) {
                QuestionDialog ask_to_open = new QuestionDialog.with_checkbox(
                    main,
                    _("Are you sure you want to open these attachments?"),
                    _("Attachments may cause damage to your system if opened.  Only open files from trusted sources."),
                    Stock._OPEN_BUTTON, Stock._CANCEL, _("Don’t _ask me again"), false
                );
                if (ask_to_open.run() == Gtk.ResponseType.OK) {
                    app.config.ask_open_attachment = !ask_to_open.is_checked;
                } else {
                    confirmed = false;
                }
            }

            if (confirmed) {
                foreach (var attachment in attachments) {
                    app.show_uri.begin(attachment.file.get_uri());
                }
            }
        }
    }

    private void set_action_enabled(string name, bool enabled) {
        SimpleAction? action = this.actions.lookup_action(name) as SimpleAction;
        if (action != null) {
            action.set_enabled(enabled);
        }
    }

    private void show_popup(View view, Gdk.EventButton? event) {
        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/components-attachment-pane-menus.ui"
        );
        var targets = new Gee.HashMap<string,GLib.Variant>();
        GLib.Variant target = view.attachment.file.get_path();
        targets[ACTION_OPEN] = target;
        targets[ACTION_REMOVE] = target;
        targets[ACTION_SAVE] = target;
        GLib.Menu model = Util.Gtk.copy_menu_with_targets(
            (GLib.Menu) builder.get_object("attachments_menu"),
            GROUP_NAME,
            targets
        );
        Gtk.Menu menu = new Gtk.Menu.from_model(model);
        menu.attach_to_widget(view, null);
        if (event != null) {
            menu.popup_at_pointer(event);
        } else {
            menu.popup_at_widget(view, CENTER, SOUTH, null);
        }
    }

    private void beep() {
        Gtk.Widget? toplevel = get_toplevel();
        if (toplevel == null) {
            Gdk.Window? window = toplevel.get_window();
            if (window != null) {
                window.beep();
            }
        }
    }

    private void on_open(GLib.SimpleAction action, GLib.Variant? param) {
        var target = get_attachment(param);
        if (target != null) {
            open_attachment(target);
        }
    }

    private void on_open_selected() {
        if (!open_selected()) {
            beep();
        }
    }

    private void on_save(GLib.SimpleAction action, GLib.Variant? param) {
        var target = get_attachment(param);
        if (target != null) {
            save_attachment(target);
        }
    }

    private void on_save_all() {
        if (!save_all()) {
            beep();
        }
    }

    private void on_save_selected() {
        if (!save_selected()) {
            beep();
        }
    }

    private void on_remove(GLib.SimpleAction action, GLib.Variant? param) {
        var target = get_attachment(param);
        if (target != null) {
            remove_attachment(target);
        }
    }

    private void on_remove_selected() {
        if (!remove_selected()) {
            beep();
        }
    }

    private void on_select_all() {
        this.attachments_view.select_all();
    }

    private void on_child_activated() {
        open_selected();
    }

    private void on_selected_changed() {
        update_actions();
    }

	private bool on_attachment_popup_menu(Gtk.Widget widget) {
        bool ret = Gdk.EVENT_PROPAGATE;
        Gtk.Window parent = get_toplevel() as Gtk.Window;
        if (parent != null) {
            Gtk.FlowBoxChild? focus = parent.get_focus() as Gtk.FlowBoxChild;
            if (focus != null && focus.parent == this.attachments_view) {
                show_popup((View) focus.get_child(), null);
                ret = Gdk.EVENT_STOP;
            }
        }
        return ret;
	}

	private bool on_attachment_button_press(Gtk.Widget widget,
                                            Gdk.EventButton event) {
        bool ret = Gdk.EVENT_PROPAGATE;
		if (event.triggers_context_menu()) {
            Gtk.FlowBoxChild? child = this.attachments_view.get_child_at_pos(
                (int) event.x,
                (int) event.y
            );
            if (child != null) {
                show_popup((View) child.get_child(), event);
                ret = Gdk.EVENT_STOP;
            }
		}
        return ret;
	}
}
