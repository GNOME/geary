/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */


internal class Accounts.EditorRow<PaneType> : Gtk.ListBoxRow {

    private const string DND_ATOM = "geary-editor-row";
    private const Gtk.TargetEntry[] DRAG_ENTRIES = {
        { DND_ATOM, Gtk.TargetFlags.SAME_APP, 0 }
    };


    protected Gtk.Box layout {
        get;
        private set;
        default = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5); }

    private Gtk.Container drag_handle;
    private bool drag_picked_up = false;
    private bool drag_entered = false;


    public signal void move_to(int new_position);
    public signal void dropped(EditorRow target);


    public EditorRow() {

        get_style_context().add_class("geary-settings");
        get_style_context().add_class("geary-labelled-row");

        // We'd like to add the drag handle only when needed, but
        // GNOME/gtk#1495 prevents us from doing so.
        Gtk.EventBox drag_box = new Gtk.EventBox();
        drag_box.add(
            new Gtk.Image.from_icon_name(
                "list-drag-handle-symbolic", Gtk.IconSize.BUTTON
            )
        );
        this.drag_handle = new Gtk.Grid();
        this.drag_handle.valign = Gtk.Align.CENTER;
        this.drag_handle.add(drag_box);
        this.drag_handle.show_all();
        this.drag_handle.hide();
        // Translators: Tooltip for dragging list items
        this.drag_handle.set_tooltip_text(_("Drag to move this item"));

        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);
        box.add(drag_handle);
        box.add(this.layout);
        box.show();
        add(box);

        this.layout.show();
        this.show();

         this.size_allocate.connect((allocation) => {
            if (allocation.width < 500) {
                if (this.layout.orientation == Gtk.Orientation.HORIZONTAL) {
                    this.layout.orientation = Gtk.Orientation.VERTICAL;
                }
            } else if (this.layout.orientation == Gtk.Orientation.VERTICAL) {
                this.layout.orientation = Gtk.Orientation.HORIZONTAL;
            }
        });
    }

    public virtual void activated(PaneType pane) {
        // No-op by default
    }

    public override bool key_press_event(Gdk.EventKey event) {
        bool ret = Gdk.EVENT_PROPAGATE;

        if (event.state == Gdk.ModifierType.CONTROL_MASK) {
            int index = get_index();
            if (event.keyval == Gdk.Key.Up) {
                index -= 1;
                if (index >= 0) {
                    move_to(index);
                    ret = Gdk.EVENT_STOP;
                }
            } else if (event.keyval == Gdk.Key.Down) {
                index += 1;
                Gtk.ListBox? parent = get_parent() as Gtk.ListBox;
                if (parent != null &&
                    index < parent.get_children().length() &&
                    !(parent.get_row_at_index(index) is AddRow)) {
                    move_to(index);
                    ret = Gdk.EVENT_STOP;
                }
            }
        }

        if (ret != Gdk.EVENT_STOP) {
            ret = base.key_press_event(event);
        }

        return ret;
    }

    /** Adds a drag handle to the row and enables drag signals. */
    protected void enable_drag() {
        Gtk.drag_source_set(
            this.drag_handle,
            Gdk.ModifierType.BUTTON1_MASK,
            DRAG_ENTRIES,
            Gdk.DragAction.MOVE
        );

        Gtk.drag_dest_set(
            this,
            // No highlight, we'll take care of that ourselves so we
            // can avoid highlighting the row that was picked up
            Gtk.DestDefaults.MOTION | Gtk.DestDefaults.DROP,
            DRAG_ENTRIES,
            Gdk.DragAction.MOVE
        );

        this.drag_handle.drag_begin.connect(on_drag_begin);
        this.drag_handle.drag_end.connect(on_drag_end);
        this.drag_handle.drag_data_get.connect(on_drag_data_get);

        this.drag_motion.connect(on_drag_motion);
        this.drag_leave.connect(on_drag_leave);
        this.drag_data_received.connect(on_drag_data_received);

        this.drag_handle.get_style_context().add_class("geary-drag-handle");
        this.drag_handle.show();

        get_style_context().add_class("geary-draggable");
    }


    private void on_drag_begin(Gdk.DragContext context) {
        // Draw a nice drag icon
        Gtk.Allocation alloc = Gtk.Allocation();
        this.get_allocation(out alloc);

        Cairo.ImageSurface surface = new Cairo.ImageSurface(
            Cairo.Format.ARGB32, alloc.width, alloc.height
        );
        Cairo.Context paint = new Cairo.Context(surface);


        Gtk.StyleContext style = get_style_context();
        style.add_class("geary-drag-icon");
        draw(paint);
        style.remove_class("geary-drag-icon");

        int x, y;
        this.drag_handle.translate_coordinates(this, 0, 0, out x, out y);
        surface.set_device_offset(-x, -y);
        Gtk.drag_set_icon_surface(context, surface);

        // Set a visual hint that the row is being dragged
        style.add_class("geary-drag-source");
        this.drag_picked_up = true;
    }

    private void on_drag_end(Gdk.DragContext context) {
        get_style_context().remove_class("geary-drag-source");
        this.drag_picked_up = false;
    }

    private bool on_drag_motion(Gdk.DragContext context,
                                int x, int y,
                                uint time_) {
        if (!this.drag_entered) {
            this.drag_entered = true;

            // Don't highlight the same row that was picked up
            if (!this.drag_picked_up) {
                Gtk.ListBox? parent = get_parent() as Gtk.ListBox;
                if (parent != null) {
                    parent.drag_highlight_row(this);
                }
            }
        }

        return true;
    }

    private void on_drag_leave(Gdk.DragContext context,
                               uint time_) {
        if (!this.drag_picked_up) {
            Gtk.ListBox? parent = get_parent() as Gtk.ListBox;
            if (parent != null) {
                parent.drag_unhighlight_row();
            }
        }
        this.drag_entered = false;
    }

    private void on_drag_data_get(Gdk.DragContext context,
                                  Gtk.SelectionData selection_data,
                                  uint info, uint time_) {
        selection_data.set(
            Gdk.Atom.intern_static_string(DND_ATOM), 8,
            get_index().to_string().data
        );
    }

    private void on_drag_data_received(Gdk.DragContext context,
                                       int x, int y,
                                       Gtk.SelectionData selection_data,
                                       uint info, uint time_) {
        int drag_index = int.parse((string) selection_data.get_data());
        Gtk.ListBox? parent = this.get_parent() as Gtk.ListBox;
        if (parent != null) {
            EditorRow? drag_row = parent.get_row_at_index(drag_index) as EditorRow;
            if (drag_row != null && drag_row != this) {
                drag_row.dropped(this);
            }
        }
    }

}


internal class Accounts.LabelledEditorRow<PaneType,V> : EditorRow<PaneType> {


    public Gtk.Label label { get; private set; default = new Gtk.Label(""); }
    public V value { get; private set; }


    public LabelledEditorRow(string label, V value) {
        this.label.halign = Gtk.Align.START;
        this.label.valign = Gtk.Align.CENTER;
        this.label.hexpand = true;
        this.label.set_text(label);
        this.label.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR);
        this.label.set_line_wrap(true);
        this.label.show();
        this.layout.add(this.label);

        bool expand_label = true;
        this.value = value;
        Gtk.Widget? widget = value as Gtk.Widget;
        if (widget != null) {
            Gtk.Entry? entry = value as Gtk.Entry;
            if (entry != null) {
                expand_label = false;
                entry.hexpand = true;
            }
            Gtk.Label? vlabel = value as Gtk.Label;
            if (vlabel != null) {
                vlabel.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR);
                vlabel.set_line_wrap(true);
            }

            widget.halign = Gtk.Align.START;
            widget.valign = Gtk.Align.CENTER;
            widget.show();
            this.layout.add(widget);
        }

        this.label.hexpand = expand_label;
    }

    public void set_dim_label(bool is_dim) {
        if (is_dim) {
            this.label.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
        } else {
            this.label.get_style_context().remove_class(Gtk.STYLE_CLASS_DIM_LABEL);
        }
    }

}


internal class Accounts.AddRow<PaneType> : EditorRow<PaneType> {


    public AddRow() {
        get_style_context().add_class("geary-add-row");
        Gtk.Image add_icon = new Gtk.Image.from_icon_name(
            "list-add-symbolic", Gtk.IconSize.BUTTON
        );
        add_icon.set_hexpand(true);
        add_icon.show();

        this.layout.add(add_icon);
    }

}


internal class Accounts.ServiceProviderRow<PaneType> :
    LabelledEditorRow<PaneType,Gtk.Label> {


    public ServiceProviderRow(Geary.ServiceProvider provider,
                              string other_type_label) {
        string? label = null;
        switch (provider) {
        case Geary.ServiceProvider.GMAIL:
            label = _("Gmail");
            break;

        case Geary.ServiceProvider.OUTLOOK:
            label = _("Outlook.com");
            break;

        case Geary.ServiceProvider.OTHER:
            label = other_type_label;
            break;
        }

        base(
            // Translators: Label describes the service provider
            // hosting the email account, e.g. Gmail, Yahoo, or some
            // other generic IMAP service.
            _("Service provider"),
            new Gtk.Label(label)
        );

        // Can't change this, so deactivate and dim out
        set_activatable(false);
        this.value.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
    }

}


internal abstract class Accounts.AccountRow<PaneType,V> :
    LabelledEditorRow<PaneType,V> {


    internal Geary.AccountInformation account { get; private set; }


    protected AccountRow(Geary.AccountInformation account, string label, V value) {
        base(label, value);
        this.account = account;
        this.account.changed.connect(on_account_changed);

        set_dim_label(true);
    }

    ~AccountRow() {
        this.account.changed.disconnect(on_account_changed);
    }

    public abstract void update();

    private void on_account_changed() {
        update();
    }

}


private abstract class Accounts.ServiceRow<PaneType,V> : AccountRow<PaneType,V> {


    internal Geary.ServiceInformation service { get; private set; }

    protected virtual bool is_value_editable {
        get {
            return (
                this.account.service_provider == Geary.ServiceProvider.OTHER &&
                !this.is_goa_account
            );
        }
    }

    // XXX convenience method until we get a better way of doing this.
    protected bool is_goa_account {
        get { return (this.account.mediator is GoaMediator); }
    }


    protected ServiceRow(Geary.AccountInformation account,
                         Geary.ServiceInformation service,
                         string label,
                         V value) {
        base(account, label, value);
        this.service = service;
        this.service.notify.connect_after(on_notify);

        bool is_editable = this.is_value_editable;
        set_activatable(is_editable);

        Gtk.Widget? widget = value as Gtk.Widget;
        if (widget != null && !is_editable) {
            if (widget is Gtk.Label) {
                widget.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
            } else {
                widget.set_sensitive(false);
            }
        }
    }

    ~ServiceRow() {
        this.service.notify.disconnect(on_notify);
    }

    private void on_notify() {
        update();
    }

}


/** Interface for rows that use a validator for editable values. */
internal interface Accounts.ValidatingRow<PaneType> : EditorRow<PaneType> {


    /** The row's validator */
    public abstract Components.Validator validator { get; protected set; }

    /** Determines if the row's value has actually changed. */
    public abstract bool has_changed { get; }

    /** Fired when validated and the value has actually changed. */
    public signal void changed();

    /** Fired when validated and the value has actually changed. */
    public signal void committed();

    /**
     * Hooks up signals to the validator.
     *
     * Implementing classes should call this in their constructor
     * after having constructed a validator
     */
    protected void setup_validator() {
        this.validator.changed.connect(on_validator_changed);
        this.validator.activated.connect(on_validator_check_commit);
        this.validator.focus_lost.connect(on_validator_check_commit);
    }

    /**
     * Called when the row's value should be stored.
     *
     * This is only called when the row's value has changed, is
     * valid, and the user has activated or changed to a different
     * row.
     */
    protected virtual void commit() {
        // noop
    }

    private void on_validator_changed() {
        if (this.has_changed) {
            changed();
        }
    }

    private void on_validator_check_commit() {
        if (this.has_changed) {
            commit();
            committed();
        }
    }

}


internal class Accounts.TlsComboBox : Gtk.ComboBox {

    private const string INSECURE_ICON = "channel-insecure-symbolic";
    private const string SECURE_ICON = "channel-secure-symbolic";


    public string label { get; private set; default = ""; }


    public Geary.TlsNegotiationMethod method {
        get {
            try {
                return Geary.TlsNegotiationMethod.for_value(this.active_id);
            } catch {
                return Geary.TlsNegotiationMethod.TRANSPORT;
            }
        }
        set {
            this.active_id = value.to_value();
        }
    }


    public TlsComboBox() {
        // Translators: This label describes what form of transport
        // security (TLS, StartTLS, etc) used by an account's IMAP or SMTP
        // service.
        this.label = _("Connection security");

        Gtk.ListStore store = new Gtk.ListStore(
            3, typeof(string), typeof(string), typeof(string)
        );
        Gtk.TreeIter iter;
        store.append(out iter);
        store.set(
            iter,
            0, Geary.TlsNegotiationMethod.NONE.to_value(),
            1, INSECURE_ICON,
            2, _("None")
        );
        store.append(out iter);
        store.set(
            iter,
            0, Geary.TlsNegotiationMethod.START_TLS.to_value(),
            1, SECURE_ICON,
            2, _("StartTLS")
        );
        store.append(out iter);
        store.set(
            iter,
            0, Geary.TlsNegotiationMethod.TRANSPORT.to_value(),
            1, SECURE_ICON,
            2, _("TLS")
        );

        this.model = store;
        set_id_column(0);

        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText();
        text_renderer.ellipsize = Pango.EllipsizeMode.END;
        pack_start(text_renderer, true);
        add_attribute(text_renderer, "text", 2);

        Gtk.CellRendererPixbuf icon_renderer = new Gtk.CellRendererPixbuf();
        pack_start(icon_renderer, true);
        add_attribute(icon_renderer, "icon_name", 1);
    }

}


internal class Accounts.OutgoingAuthComboBox : Gtk.ComboBox {


    public string label { get; private set; }

    public Geary.Credentials.Requirement source {
        get {
            try {
                return Geary.Credentials.Requirement.for_value(this.active_id);
            } catch {
                return Geary.Credentials.Requirement.USE_INCOMING;
            }
        }
        set {
            this.active_id = value.to_value();
        }
    }


    public OutgoingAuthComboBox() {
        // Translators: Label for source of SMTP authentication
        // credentials (none, use IMAP, custom) when adding a new
        // account
        this.label = _("Login");

        Gtk.ListStore store = new Gtk.ListStore(
            2, typeof(string), typeof(string)
        );
        Gtk.TreeIter iter;

        store.append(out iter);
        store.set(
            iter,
            0,
            Geary.Credentials.Requirement.NONE.to_value(),
            1,
            // Translators: ComboBox value for source of SMTP
            // authentication credentials (none) when adding a new
            // account
            _("No login needed")
        );

        store.append(out iter);
        store.set(
            iter,
            0,
            Geary.Credentials.Requirement.USE_INCOMING.to_value(),
            1,
            // Translators: ComboBox value for source of SMTP
            // authentication credentials (use IMAP) when adding a new
            // account
            _("Use same login as receiving")
        );

        store.append(out iter);
        store.set(
            iter,
            0,
            Geary.Credentials.Requirement.CUSTOM.to_value(),
            1,
            // Translators: ComboBox value for source of SMTP
            // authentication credentials (custom) when adding a new
            // account
            _("Use a different login")
        );

        this.model = store;
        set_id_column(0);

        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText();
        text_renderer.ellipsize = Pango.EllipsizeMode.END;
        pack_start(text_renderer, true);
        add_attribute(text_renderer, "text", 1);
    }

}


/**
 * Displaying and manages validation of popover-based forms.
 */
internal class Accounts.EditorPopover : Gtk.Popover {


    internal Gtk.Grid layout {
        get; private set; default = new Gtk.Grid();
    }

    protected Gtk.Widget popup_focus = null;


    public EditorPopover() {
        get_style_context().add_class("geary-editor");

        this.layout.orientation = Gtk.Orientation.VERTICAL;
        this.layout.set_row_spacing(6);
        this.layout.set_column_spacing(12);
        this.layout.show();
        add(this.layout);

        this.closed.connect_after(on_closed);
    }

    ~EditorPopover() {
        this.closed.disconnect(on_closed);
    }

    /** {@inheritDoc} */
    public new void popup() {
        // Work-around GTK+ issue #1138
        Gtk.Widget target = get_relative_to();

        Gtk.Allocation content_area;
        target.get_allocation(out content_area);

        Gtk.StyleContext style = target.get_style_context();
        Gtk.StateFlags flags = style.get_state();
        Gtk.Border margin = style.get_margin(flags);

        content_area.x = margin.left;
        content_area.y =  margin.bottom;
        content_area.width -= (content_area.x + margin.right);
        content_area.height -= (content_area.y + margin.top);

        set_pointing_to(content_area);

        base.popup();

        if (this.popup_focus != null) {
            this.popup_focus.grab_focus();
        }
    }

    public void add_labelled_row(string label, Gtk.Widget value) {
        Gtk.Label label_widget = new Gtk.Label(label);
        label_widget.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
        label_widget.halign = Gtk.Align.END;
        label_widget.show();

        this.layout.add(label_widget);
        this.layout.attach_next_to(value, label_widget, Gtk.PositionType.RIGHT);
    }

    private void on_closed() {
        destroy();
    }

}
