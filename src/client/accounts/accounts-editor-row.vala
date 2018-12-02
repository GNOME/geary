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


    protected Gtk.Grid layout { get; private set; default = new Gtk.Grid(); }

    private Gtk.Container drag_handle;


    public signal void dropped(EditorRow target);


    public EditorRow() {
        get_style_context().add_class("geary-settings");

        this.layout.orientation = Gtk.Orientation.HORIZONTAL;
        this.layout.show();
        add(this.layout);

        // We'd like to add the drag handle only when needed, but
        // GNOME/gtk#1495 prevents us from doing so.
        Gtk.EventBox drag_box = new Gtk.EventBox();
        drag_box.add(
            new Gtk.Image.from_icon_name(
                "open-menu-symbolic", Gtk.IconSize.BUTTON
            )
        );
        this.drag_handle = new Gtk.Grid();
        this.drag_handle.valign = Gtk.Align.CENTER;
        this.drag_handle.add(drag_box);
        this.drag_handle.show_all();
        this.drag_handle.hide();
        // Translators: Tooltip for dragging list items
        this.drag_handle.set_tooltip_text(_("Drag to move this item"));
        this.layout.add(drag_handle);

        this.show();
    }

    public virtual void activated(PaneType pane) {
        // No-op by default
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
            Gtk.DestDefaults.ALL,
            DRAG_ENTRIES,
            Gdk.DragAction.MOVE
        );

        this.drag_handle.drag_data_get.connect(on_drag_data_get);
        this.drag_data_received.connect(on_drag_data_received);
        this.drag_handle.get_style_context().add_class("geary-drag-handle");
        this.drag_handle.show();

        get_style_context().add_class("geary-draggable");
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
        this.label.hexpand = true;
        this.label.halign = Gtk.Align.START;
        this.label.valign = Gtk.Align.CENTER;
        this.label.set_text(label);
        this.label.show();
        this.layout.add(this.label);

        this.value = value;
        Gtk.Widget? widget = value as Gtk.Widget;
        if (widget != null) {
            widget.valign = Gtk.Align.CENTER;
            widget.show();
            this.layout.add(widget);
        }
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
        string? label = other_type_label;
        switch (provider) {
        case Geary.ServiceProvider.GMAIL:
            label = _("Gmail");
            break;

        case Geary.ServiceProvider.OUTLOOK:
            label = _("Outlook.com");
            break;

        case Geary.ServiceProvider.YAHOO:
            label = _("Yahoo");
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


    public AccountRow(Geary.AccountInformation account, string label, V value) {
        base(label, value);
        this.account = account;
        this.account.information_changed.connect(on_account_changed);

        set_dim_label(true);
    }

    ~AccountRow() {
        this.account.information_changed.disconnect(on_account_changed);
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
        get { return (this.service.mediator is GoaMediator); }
    }


    public ServiceRow(Geary.AccountInformation account,
                      Geary.ServiceInformation service,
                      string label,
                      V value) {
        base(account, label, value);
        this.service = service;
        this.service.notify.connect(on_notify);

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
		pack_start(text_renderer, true);
		add_attribute(text_renderer, "text", 2);

        Gtk.CellRendererPixbuf icon_renderer = new Gtk.CellRendererPixbuf();
		pack_start(icon_renderer, true);
		add_attribute(icon_renderer, "icon_name", 1);
    }

}


internal class Accounts.SmtpAuthComboBox : Gtk.ComboBoxText {


    public string label { get; private set; }

    public Geary.SmtpCredentials source {
        get {
            try {
                return Geary.SmtpCredentials.for_value(this.active_id);
            } catch {
                return Geary.SmtpCredentials.IMAP;
            }
        }
        set {
            this.active_id = value.to_value();
        }
    }


    public SmtpAuthComboBox() {
        // Translators: Label for source of SMTP authentication
        // credentials (none, use IMAP, custom) when adding a new
        // account
        this.label = _("Login");

        // Translators: ComboBox value for source of SMTP
        // authentication credentials (none) when adding a new account
        append(Geary.SmtpCredentials.NONE.to_value(), _("No login needed"));

        // Translators: ComboBox value for source of SMTP
        // authentication credentials (use IMAP) when adding a new
        // account
        append(Geary.SmtpCredentials.IMAP.to_value(), _("Use IMAP login"));

        // Translators: ComboBox value for source of SMTP
        // authentication credentials (custom) when adding a new
        // account
        append(Geary.SmtpCredentials.CUSTOM.to_value(), _("Use different login"));
    }

}


/**
 * Displaying and manages validation of popover-based forms.
 */
internal class Accounts.EditorPopover : Gtk.Popover {


    internal Gtk.Grid layout {
        get; private set; default = new Gtk.Grid();
    }

    internal Gee.Collection<Components.Validator> validators {
        owned get { return this.validator_backing.read_only_view; }
    }

    protected Gtk.Widget popup_focus = null;

    private Gee.Collection<Components.Validator> validator_backing =
        new Gee.LinkedList<Components.Validator>();


    /**
     * Emitted when a validated widget is activated all are valid.
     *
     * This signal will be emitted when all of the following are true:
     *
     * 1. At least one validator has been added to the popover
     * 2. The user activates an entry that is being monitored by a
     *    validator
     * 3. The validation for the has completed (i.e. is not in
     *    progress)
     * 4. All validators are in the valid state
     */
    public override signal void valid_activated();


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

    /** {@inheritdoc} */
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

    public void add_validator(Components.Validator validator) {
        validator.activated.connect(on_validator_activated);
        this.validator_backing.add(validator);
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

    private void on_validator_activated() {
        if (Geary.traverse(this.validator_backing).all(
                (v) => v.state == Components.Validator.Validity.VALID)) {
            valid_activated();
        }
    }

}


internal class PropertyCommand<T> : Application.Command {


    private Geary.AccountInformation account;
    private GLib.Object object;
    private string property_name;
    private T? new_value;
    private T? old_value;


    public PropertyCommand(Geary.AccountInformation account,
                           GLib.Object object,
                           string property_name,
                           T? new_value,
                           string? undo_label = null,
                           string? redo_label = null,
                           string? executed_label = null,
                           string? undone_label = null) {
        this.account = account;
        this.object = object;
        this.property_name = property_name;
        this.new_value = new_value;

        this.object.get(this.property_name, ref this.old_value);

        this.undo_label = undo_label.printf(this.old_value);
        this.redo_label = redo_label.printf(this.new_value);
        this.executed_label = executed_label.printf(this.new_value);
        this.undone_label = undone_label.printf(this.old_value);
    }

    public async override void execute(GLib.Cancellable? cancellable) {
        this.object.set(this.property_name, this.new_value);
        this.account.information_changed();
    }

    public async override void undo(GLib.Cancellable? cancellable) {
        this.object.set(this.property_name, this.old_value);
        this.account.information_changed();
    }

}
