/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An account editor pane for editing a specific account's preferences.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_edit_pane.ui")]
internal class Accounts.EditorEditPane : Gtk.Grid, EditorPane, AccountPane {


    internal Geary.AccountInformation account { get ; protected set; }

    /** Command stack for edit pane user commands. */
    internal Application.CommandStack commands {
        get; private set; default = new Application.CommandStack();
    }

    protected weak Accounts.Editor editor { get; set; }

    [GtkChild]
    private Gtk.HeaderBar header;

    [GtkChild]
    private Gtk.Grid pane_content;

    [GtkChild]
    private Gtk.Adjustment pane_adjustment;

    [GtkChild]
    private Gtk.ListBox details_list;

    [GtkChild]
    private Gtk.ListBox senders_list;

    [GtkChild]
    private Gtk.Frame signature_frame;

    private ClientWebView signature_preview;
    private bool signature_changed = false;

    [GtkChild]
    private Gtk.ListBox settings_list;

    [GtkChild]
    private Gtk.Button undo_button;

    [GtkChild]
    private Gtk.Button remove_button;


    public EditorEditPane(Editor editor, Geary.AccountInformation account) {
        this.editor = editor;
        this.account = account;

        this.pane_content.set_focus_vadjustment(this.pane_adjustment);

        this.details_list.set_header_func(Editor.seperator_headers);
        this.details_list.add(new NicknameRow(account));

        this.senders_list.set_header_func(Editor.seperator_headers);
        foreach (Geary.RFC822.MailboxAddress sender
                 in account.get_sender_mailboxes()) {
            this.senders_list.add(new MailboxRow(account, sender));
        }
        this.senders_list.add(new AddMailboxRow());

        this.signature_preview = new ClientWebView(
            ((GearyApplication) editor.application).config
        );
        this.signature_preview.events = (
            this.signature_preview.events | Gdk.EventType.FOCUS_CHANGE
        );
        this.signature_preview.content_loaded.connect(() => {
                // Only enable editability after the content has fully
                // loaded to avoid the WebProcess crashing.
                this.signature_preview.set_editable.begin(true, null);
            });
        this.signature_preview.document_modified.connect(() => {
                this.signature_changed = true;
            });
        this.signature_preview.focus_out_event.connect(() => {
                // This event will also be fired if the top-level
                // window loses focus, e.g. if the user alt-tabs away,
                // so don't execute the command if the signature web
                // view no longer the focus widget
                if (!this.signature_preview.is_focus &&
                    this.signature_changed) {
                    this.commands.execute.begin(
                        new SignatureChangedCommand(
                            this.signature_preview, account
                        ),
                        null
                    );
                }
                return Gdk.EVENT_PROPAGATE;
            });

        this.signature_preview.show();
        this.signature_preview.load_html(
            Geary.HTML.smart_escape(account.email_signature)
        );

        this.signature_frame.add(this.signature_preview);

        this.settings_list.set_header_func(Editor.seperator_headers);
        this.settings_list.add(new EmailPrefetchRow(this));

        this.remove_button.set_visible(
            !this.editor.accounts.is_goa_account(account)
        );

        this.account.information_changed.connect(on_account_changed);
        update_header();

        this.commands.executed.connect(on_command);
        this.commands.undone.connect(on_command);
        this.commands.redone.connect(on_command);
    }

    ~EditorEditPane() {
        this.account.information_changed.disconnect(on_account_changed);

        this.commands.executed.disconnect(on_command);
        this.commands.undone.disconnect(on_command);
        this.commands.redone.disconnect(on_command);
    }

    internal string? get_default_name() {
        string? name = account.primary_mailbox.name;

        if (Geary.String.is_empty_or_whitespace(name)) {
            name = Environment.get_real_name();
            if (Geary.String.is_empty(name) || name == "Unknown") {
                name = null;
            }
        }

        return name;
    }

    internal Gtk.HeaderBar get_header() {
        return this.header;
    }

    internal void pane_shown() {
        update_actions();
    }

    internal void undo() {
        this.commands.undo.begin(null);
    }

    internal void redo() {
        this.commands.redo.begin(null);
    }

    private void update_actions() {
        this.editor.get_action(GearyController.ACTION_UNDO).set_enabled(
            this.commands.can_undo
        );
        this.editor.get_action(GearyController.ACTION_REDO).set_enabled(
            this.commands.can_redo
        );

        Application.Command next_undo = this.commands.peek_undo();
        this.undo_button.set_tooltip_text(
            (next_undo != null && next_undo.undo_label != null)
            ? next_undo.undo_label : ""
        );
    }

    private void on_account_changed() {
        update_header();
    }

    private void on_command() {
        update_actions();
    }

    [GtkCallback]
    private void on_setting_activated(Gtk.ListBoxRow row) {
        EditorRow<EditorEditPane>? setting = row as EditorRow<EditorEditPane>;
        if (setting != null) {
            setting.activated(this);
        }
    }

    [GtkCallback]
    private void on_server_settings_clicked() {
        this.editor.push(new EditorServersPane(this.editor, this.account));
    }

    [GtkCallback]
    private void on_remove_account_clicked() {
        if (!this.editor.accounts.is_goa_account(account)) {
            this.editor.push(new EditorRemovePane(this.editor, this.account));
        }
    }

    [GtkCallback]
    private void on_back_button_clicked() {
        this.editor.pop();
    }

    [GtkCallback]
    private bool on_list_keynav_failed(Gtk.Widget widget,
                                       Gtk.DirectionType direction) {
        bool ret = Gdk.EVENT_PROPAGATE;
        Gtk.Container? next = null;
        if (direction == Gtk.DirectionType.DOWN) {
            if (widget == this.details_list) {
                next = this.senders_list;
            } else if (widget == this.senders_list) {
                this.signature_preview.grab_focus();
            } else if (widget == this.signature_preview) {
                next = this.settings_list;
            }
        } else if (direction == Gtk.DirectionType.UP) {
            if (widget == this.settings_list) {
                this.signature_preview.grab_focus();
            } else if (widget == this.signature_preview) {
                next = this.senders_list;
            } else if (widget == this.senders_list) {
                next = this.details_list;
            }
        }

        if (next != null) {
            next.child_focus(direction);
            ret = Gdk.EVENT_STOP;
        }
        return ret;
    }

}


private class Accounts.NicknameRow : AccountRow<EditorEditPane,Gtk.Label> {


    public NicknameRow(Geary.AccountInformation account) {
        base(
            account,
            // Translators: Label in the account editor for the user's
            // custom name for an account.
            _("Account name"),
            new Gtk.Label("")
        );
        update();
    }

    public override void activated(EditorEditPane pane) {
        EditorPopover popover = new EditorPopover();

        string? value = this.account.nickname;
        Gtk.Entry entry = new Gtk.Entry();
        entry.set_text(value ?? "");
        entry.set_placeholder_text(value ?? "");
        entry.set_width_chars(20);
        entry.activate.connect(() => {
                pane.commands.execute.begin(
                    new PropertyCommand<string>(
                        this.account,
                        this.account,
                        Geary.AccountInformation.PROP_NICKNAME,
                        entry.get_text(),
                        // Translators: Tooltip used to undo changing
                        // the name of an account. The string
                        // substitution is the old name of the
                        // account.
                        _("Change account name back to “%s”")
                    ),
                    null
                );
                popover.popdown();
            });
        entry.show();

        popover.add_labelled_row(
            // Translators: Label used when editing the account's
            // name.
            _("Account name:"),
            entry
        );

        popover.set_relative_to(this);
        popover.layout.add(entry);
        popover.popup();
    }

    public override void update() {
        this.value.set_text(this.account.nickname);
    }

}


private class Accounts.AddMailboxRow : AddRow<EditorEditPane> {


    public AddMailboxRow() {
        // Translators: Tooltip for adding a new email sender/from
        // address's address to an account
        this.set_tooltip_text(_("Add a new sender email address"));
    }

    public override void activated(EditorEditPane pane) {
        MailboxEditorPopover popover = new MailboxEditorPopover(
            pane.get_default_name() ?? "", "", false
        );
        popover.activated.connect(() => {
                pane.commands.execute.begin(
                    new AppendMailboxCommand(
                        (Gtk.ListBox) get_parent(),
                        new MailboxRow(
                            pane.account,
                            new Geary.RFC822.MailboxAddress(
                                popover.display_name,
                                popover.address
                            )
                        )
                    ),
                    null
                );
                popover.popdown();
            });

        popover.set_relative_to(this);
        popover.popup();
    }
}


private class Accounts.MailboxRow : AccountRow<EditorEditPane,Gtk.Label> {


    internal Geary.RFC822.MailboxAddress mailbox;


    public MailboxRow(Geary.AccountInformation account,
                      Geary.RFC822.MailboxAddress mailbox) {
        base(account, "", new Gtk.Label(""));
        this.mailbox = mailbox;

        update();
    }

    public override void activated(EditorEditPane pane) {
        MailboxEditorPopover popover = new MailboxEditorPopover(
            this.mailbox.name ?? "",
            this.mailbox.address,
            this.account.get_sender_mailboxes().size > 1
        );
        popover.activated.connect(() => {
                pane.commands.execute.begin(
                    new UpdateMailboxCommand(
                        this,
                        new Geary.RFC822.MailboxAddress(
                            popover.display_name,
                            popover.address
                        )
                    ),
                    null
                );
                popover.popdown();
            });
        popover.remove_clicked.connect(() => {
                pane.commands.execute.begin(
                    new RemoveMailboxCommand(this), null
                );
                popover.popdown();
            });

        popover.set_relative_to(this);
        popover.popup();
    }

    public override void update() {
        string? name = this.mailbox.name;
        if (Geary.String.is_empty_or_whitespace(name)) {
            // Translators: Label used to indicate the user has
            // provided no display name for one of their sender
            // email addresses in their account settings.
            name = _("Name not set");
            set_dim_label(true);
        } else {
            set_dim_label(false);
        }

        this.label.set_text(name);
        this.value.set_text(mailbox.address.strip());
    }

}

internal class Accounts.MailboxEditorPopover : EditorPopover {


    public string display_name { get; private set; }
    public string address { get; private set; }


    private Gtk.Entry name_entry = new Gtk.Entry();
    private Gtk.Entry address_entry = new Gtk.Entry();
    private Components.EmailValidator address_validator;
    private Gtk.Button remove_button;

    public signal void activated();
    public signal void remove_clicked();


    public MailboxEditorPopover(string? display_name,
                                string? address,
                                bool can_remove) {
        this.display_name = display_name;
        this.address = address;

        this.name_entry.set_text(display_name ?? "");
        this.name_entry.set_placeholder_text(
            // Translators: This is used as a placeholder for the
            // display name for an email address when editing a user's
            // sender address preferences for an account.
            _("Sender Name")
        );
        this.name_entry.set_width_chars(20);
        this.name_entry.changed.connect(on_name_changed);
        this.name_entry.activate.connect(on_activate);
        this.name_entry.show();

        this.address_entry.input_purpose = Gtk.InputPurpose.EMAIL;
        this.address_entry.set_text(address ?? "");
        this.address_entry.set_placeholder_text(
            // Translators: This is used as a placeholder for the
            // address part of an email address when editing a user's
            // sender address preferences for an account.
            _("person@example.com")
        );
        this.address_entry.set_width_chars(20);
        this.address_entry.changed.connect(on_address_changed);
        this.address_entry.activate.connect(on_activate);
        this.address_entry.show();

        this.address_validator =
            new Components.EmailValidator(this.address_entry);

        this.remove_button = new Gtk.Button.with_label(_("Remove"));
        this.remove_button.halign = Gtk.Align.END;
        this.remove_button.get_style_context().add_class(
            "geary-setting-remove"
        );
        this.remove_button.get_style_context().add_class(
            Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION
        );
        this.remove_button.clicked.connect(on_remove_clicked);
        this.remove_button.show();

        add_labelled_row(
            // Translators: Label used for the display name part of an
            // email address when editing a user's sender address
            // preferences for an account.
            _("Sender name:"),
            this.name_entry
        );
        add_labelled_row(
            // Translators: Label used for the address part of an
            // email address when editing a user's sender address
            // preferences for an account.
            _("Email address:"),
            this.address_entry
        );

        if (can_remove) {
            this.layout.attach(this.remove_button, 0, 2, 2, 1);
        }

        this.popup_focus = this.name_entry;
    }

    ~MailboxEditorPopover() {
        this.name_entry.changed.disconnect(on_name_changed);
        this.name_entry.activate.disconnect(on_activate);

        this.address_entry.changed.disconnect(on_address_changed);
        this.address_entry.activate.disconnect(on_activate);

        this.remove_button.clicked.disconnect(on_remove_clicked);
    }

    private void on_name_changed() {
        this.display_name = this.name_entry.get_text().strip();
    }

    private void on_address_changed() {
        this.address = this.address_entry.get_text().strip();
    }

    private void on_remove_clicked() {
        remove_clicked();
    }

    private void on_activate() {
        if (this.address != "" && this.address_validator.is_valid) {
            activated();
        }
    }

}


internal class Accounts.AppendMailboxCommand : Application.Command {


    private Gtk.ListBox senders_list;
    private MailboxRow new_row = null;

    private int mailbox_index;


    public AppendMailboxCommand(Gtk.ListBox senders_list, MailboxRow new_row) {
        this.senders_list = senders_list;
        this.new_row = new_row;

        this.mailbox_index = new_row.account.get_sender_mailboxes().size;

        // Translators: Label used as the undo tooltip after adding an
        // new sender email address to an account. The string
        // substitution is the email address added.
        this.undo_label = _("Remove “%s”").printf(new_row.mailbox.address);
    }

    public async override void execute(GLib.Cancellable? cancellable) {
        this.senders_list.insert(this.new_row, this.mailbox_index);
        this.new_row.account.append_sender_mailbox(this.new_row.mailbox);
        this.new_row.account.information_changed();
    }

    public async override void undo(GLib.Cancellable? cancellable) {
        this.senders_list.remove(this.new_row);
        this.new_row.account.remove_sender_mailbox(this.new_row.mailbox);
        this.new_row.account.information_changed();
    }

}


internal class Accounts.UpdateMailboxCommand : Application.Command {


    private MailboxRow row;
    private Geary.RFC822.MailboxAddress new_mailbox;

    private Geary.RFC822.MailboxAddress old_mailbox;
    private int mailbox_index;


    public UpdateMailboxCommand(MailboxRow row,
                                Geary.RFC822.MailboxAddress new_mailbox) {
        this.row = row;
        this.new_mailbox = new_mailbox;

        this.old_mailbox = row.mailbox;
        this.mailbox_index =
            row.account.get_sender_mailboxes().index_of(this.old_mailbox);

        // Translators: Label used as the undo tooltip after editing a
        // sender address for an account. The string substitution is
        // the email address edited.
        this.undo_label = _("Undo changes to “%s”").printf(
            this.old_mailbox.address
        );
    }

    public async override void execute(GLib.Cancellable? cancellable) {
        this.row.mailbox = this.new_mailbox;
        this.row.account.remove_sender_mailbox(this.old_mailbox);
        this.row.account.insert_sender_mailbox(this.mailbox_index, this.new_mailbox);
        this.row.account.information_changed();
    }

    public async override void undo(GLib.Cancellable? cancellable) {
        this.row.mailbox = this.old_mailbox;
        this.row.account.remove_sender_mailbox(this.new_mailbox);
        this.row.account.insert_sender_mailbox(this.mailbox_index, this.old_mailbox);
        this.row.account.information_changed();
    }

}


internal class Accounts.RemoveMailboxCommand : Application.Command {


    private MailboxRow row;

    private Geary.RFC822.MailboxAddress mailbox;
    private int mailbox_index;
    private Gtk.ListBox list;


    public RemoveMailboxCommand(MailboxRow row) {
        this.row = row;

        this.mailbox = row.mailbox;
        this.mailbox_index =
            row.account.get_sender_mailboxes().index_of(mailbox);
        this.list = (Gtk.ListBox) row.get_parent();

        // Translators: Label used as the undo tooltip after removing
        // a sender address from an account. The string substitution
        // is the email address edited.
        this.undo_label = _("Add “%s” back").printf(this.mailbox.address);
    }

    public async override void execute(GLib.Cancellable? cancellable) {
        this.list.remove(this.row);
        this.row.account.remove_sender_mailbox(this.mailbox);
        this.row.account.information_changed();
    }

    public async override void undo(GLib.Cancellable? cancellable) {
        this.list.insert(this.row, this.mailbox_index);
        this.row.account.insert_sender_mailbox(this.mailbox_index, this.mailbox);
        this.row.account.information_changed();
    }

}


internal class Accounts.SignatureChangedCommand : Application.Command {


    private ClientWebView signature_view;
    private Geary.AccountInformation account;

    private string old_value;
    private string? new_value = null;


    public SignatureChangedCommand(ClientWebView signature_view,
                                   Geary.AccountInformation account) {
        this.signature_view = signature_view;
        this.account = account;

        this.old_value = Geary.HTML.smart_escape(account.email_signature);

        // Translators: Label used as the undo tooltip after removing
        // a sender address from an account. The string substitution
        // is the email address edited.
        this.undo_label = _("Undo signature changes");
    }

    public async override void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.new_value = yield this.signature_view.get_html();
        update_account_signature(this.new_value);
    }

    public async override void undo(GLib.Cancellable? cancellable) {
        this.signature_view.load_html(this.old_value);
        update_account_signature(this.old_value);
    }

    public async override void redo(GLib.Cancellable? cancellable) {
        this.signature_view.load_html(this.new_value);
        update_account_signature(this.new_value);
    }

    private inline void update_account_signature(string value) {
        this.account.email_signature = value;
        this.account.information_changed();
    }

}


private class Accounts.EmailPrefetchRow :
    AccountRow<EditorEditPane,Gtk.ComboBoxText> {


    private static bool row_separator(Gtk.TreeModel model, Gtk.TreeIter iter) {
        GLib.Value v;
        model.get_value(iter, 0, out v);
        return v.get_string() == ".";
    }


    public EmailPrefetchRow(EditorEditPane pane) {
        base(
            pane.account,
            // Translators: This label describes the account
            // preference for the length of time (weeks, months or
            // years) that past email should be downloaded.
            _("Download mail"),
            new Gtk.ComboBoxText()
        );
        set_activatable(false);

        this.value.set_row_separator_func(row_separator);

        // Populate the model
        get_label(14, true);
        get_label(30, true);
        get_label(90, true);
        get_label(180, true);
        get_label(365, true);
        get_label(720, true);
        get_label(1461, true);
        get_label(-1, true);

        // Update before connecting to the changed signal to avoid
        // getting a spurious command.
        update();

        this.value.changed.connect(() => {
                pane.commands.execute.begin(
                    new PropertyCommand<int>(
                        this.account,
                        this.account,
                        "prefetch-period-days",
                        int.parse(this.value.get_active_id()),
                        // Translators: Tooltip for undoing a change
                        // to the length of time that past email
                        // should be downloaded for an account. The
                        // string substitution is the duration,
                        // e.g. "1 month back".
                        _("Change download period back to: %s").printf(
                            get_label(this.account.prefetch_period_days)
                        )
                    ),
                    null
                );
            });
    }

    public override void update() {
        string id = this.account.prefetch_period_days.to_string();
        if (this.value.get_active_id() != id) {
            this.value.set_active_id(id);
        }
    }

    private string get_label(int duration, bool append = false) {
        string label = "";
        bool is_custom = false;
        switch (duration) {
        case -1:
            label = _("Everything");
            break;

        case 14:
            label = _("2 weeks back");
            break;

        case 30:
            label = _("1 month back");
            break;

        case 90:
            label = _("3 months back");
            break;

        case 180:
            label = _("6 months back");
            break;

        case 365:
            label = _("1 year back");
            break;

        case 720:
            label = _("2 years back");
            break;

        case 1461:
            label = _("4 years back");
            break;

        default:
            is_custom = true;
            label = GLib.ngettext(
                "%d day back",
                "%d days back",
                duration
            ).printf(duration);
            break;
        }

        if (append) {
            if (duration == -1 || is_custom) {
                this.value.append(".", "."); // Separator
            }
            this.value.append(duration.to_string(), label);
        }

        return label;
    }

}
