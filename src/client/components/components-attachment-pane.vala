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
public class Components.AttachmentPane : Gtk.Box {


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

            Gdk.Paintable? paintable = null;

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
                    var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(
                        stream, preview_size, preview_size, true, load_cancelled
                    );
                    pixbuf = pixbuf.apply_embedded_orientation();
                    paintable = Gdk.Texture.for_pixbuf(pixbuf);
                } else {
                    // Load the icon for this mime type
                    GLib.Icon icon = GLib.ContentType.get_icon(
                        this.gio_content_type
                    );
                    var theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
                    paintable = theme.lookup_by_gicon(
                        icon, ATTACHMENT_ICON_SIZE, window_scale, get_direction(), 0
                    );
                }
            } catch (GLib.Error error) {
                debug("Failed to load icon for attachment '%s': %s",
                      this.attachment.file.get_path(),
                      error.message);
            }

            if (paintable != null) {
                this.icon.paintable = paintable;
            }
        }

    }


    /** Determines if this pane's contents can be modified. */
    public bool edit_mode { get; private set; }

    private Gee.List<Geary.Attachment> attachments =
         new Gee.LinkedList<Geary.Attachment>();

    private Application.AttachmentManager manager;

    private GLib.SimpleActionGroup actions = new GLib.SimpleActionGroup();

    [GtkChild] private unowned Gtk.Box attachments_container;

    [GtkChild] private unowned Gtk.Button save_button;

    [GtkChild] private unowned Gtk.Button remove_button;

    private Gtk.FlowBox attachments_view;


    public AttachmentPane(bool edit_mode,
                          Application.AttachmentManager manager) {
        this.edit_mode = edit_mode;
        if (edit_mode) {
            save_button.hide();
        } else {
            remove_button.hide();
        }

        this.manager = manager;

        this.attachments_view = new Gtk.FlowBox();
        //XXX GTK4 need to check if shortcuts still work
        this.attachments_view.child_activated.connect(on_child_activated);
        this.attachments_view.selected_children_changed.connect(on_selected_changed);
        Gtk.GestureClick gesture = new Gtk.GestureClick();
        gesture.pressed.connect(on_attachment_pressed);
        this.attachments_view.add_controller(gesture);
        this.attachments_view.activate_on_single_click = false;
        this.attachments_view.max_children_per_line = 3;
        this.attachments_view.column_spacing = 6;
        this.attachments_view.row_spacing = 6;
        this.attachments_view.selection_mode = Gtk.SelectionMode.MULTIPLE;
        this.attachments_view.hexpand = true;
        this.attachments_container.append(this.attachments_view);

        this.actions.add_action_entries(action_entries, this);
        insert_action_group(GROUP_NAME, this.actions);
    }

    public void add_attachment(Geary.Attachment attachment,
                               GLib.Cancellable? cancellable) {
        View view = new View(attachment);
        this.attachments_view.append(view);
        this.attachments.add(attachment);
        view.load_icon.begin(cancellable);

        update_actions();
    }

    public void open_attachment(Geary.Attachment attachment) {
        open_attachments.begin(Geary.Collection.single(attachment));
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
        for (int i = 0; true; i++) {
            unowned var flow_child = this.attachments_view.get_child_at_index(i);
            if (flow_child == null)
                break;
            if (((View) flow_child.get_child()).attachment == attachment) {
                this.attachments_view.remove(flow_child);
                i--;
            }
        }
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
            open_attachments.begin(selected);
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

    private async void open_attachments(Gee.Collection<Geary.Attachment> attachments) {
        var main = get_root() as Application.MainWindow;
        if (main == null)
            return;

        Application.Client app = main.application;
        if (app.config.ask_open_attachment) {
            var dialog = new Adw.AlertDialog(
                _("Are you sure you want to open these attachments?"),
                _("Attachments may cause damage to your system if opened. Only open files from trusted sources."));
            dialog.add_response("cancel", _("_Cancel"));
            dialog.add_response("open", _("_Open"));
            dialog.default_response = "open";
            dialog.close_response = "cancel";

            var check = new Adw.SwitchRow();
            check.title = _("Don’t _ask me again");

            string response = yield dialog.choose(main, null);
            if (response != "open")
                return;
            app.config.ask_open_attachment = !check.active;
        }

        foreach (var attachment in attachments) {
            var launcher = new Gtk.FileLauncher(attachment.file);
            try {
                yield launcher.launch(get_native() as Gtk.Window, null);
            } catch (GLib.Error err) {
                warning("Couldn't show attachment: %s", err.message);
            }
        }
    }

    private void set_action_enabled(string name, bool enabled) {
        SimpleAction? action = this.actions.lookup_action(name) as SimpleAction;
        if (action != null) {
            action.set_enabled(enabled);
        }
    }

    private void show_popup(View view, Gdk.Rectangle? rect) {
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
        Gtk.PopoverMenu menu = new Gtk.PopoverMenu.from_model(model);
        menu.set_parent(view);
        if (rect != null) {
            menu.set_pointing_to(rect);
        }
        menu.popup();
    }

    private void beep() {
        Gtk.Native? native = get_native();
        if (native == null) {
            Gdk.Surface? surface = native.get_surface();
            if (surface != null) {
                surface.beep();
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

    private void on_attachment_pressed(Gtk.GestureClick gesture, int n_press, double x, double y) {
        var event = gesture.get_current_event();
        if (event.triggers_context_menu()) {
            Gtk.FlowBoxChild? child = this.attachments_view.get_child_at_pos(
                (int) x,
                (int) y
            );
            if (child != null) {
                Gdk.Rectangle rect = { (int) x, (int) y, 1, 1 };
                show_popup((View) child.get_child(), rect);
                //XXX GTK4?
                // ret = Gdk.EVENT_STOP;
            }
        }
    }
}
