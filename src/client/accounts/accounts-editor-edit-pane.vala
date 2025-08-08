/*
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An account editor pane for editing a specific account's preferences.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_edit_pane.ui")]
internal class Accounts.EditorEditPane : EditorPane, AccountPane, CommandPane {


    /** {@inheritDoc} */
    internal Geary.AccountInformation account { get ; protected set; }

    /** {@inheritDoc} */
    internal Application.CommandStack commands {
        get; protected set; default = new Application.CommandStack();
    }

    /** {@inheritDoc} */
    internal override bool is_operation_running { get; protected set; default = false; }

    /** {@inheritDoc} */
    internal override Cancellable? op_cancellable {
        get; protected set; default = null;
    }

    /** {@inheritDoc} */
    protected override weak Accounts.Editor editor { get; set; }

    [GtkChild] private unowned Adw.HeaderBar header;

    [GtkChild] private unowned Adw.EntryRow display_name_row;

    [GtkChild] private unowned Gtk.ListBox senders_list;

    [GtkChild] private unowned Adw.PreferencesGroup signature_bin;

    private SignatureWebView signature_preview;
    private bool signature_changed = false;

    [GtkChild] private unowned Adw.ComboRow email_prefetch_row;

    [GtkChild] private unowned Gtk.Button undo_button;

    [GtkChild] private unowned Gtk.Button remove_button;


    public EditorEditPane(Editor editor, Geary.AccountInformation account) {
        this.editor = editor;
        this.account = account;

        update_display_name();

        foreach (Geary.RFC822.MailboxAddress sender in
                 account.sender_mailboxes) {
            this.senders_list.append(new_mailbox_row(sender));
        }

        this.signature_preview = new SignatureWebView(editor.application.config);
        this.signature_preview.add_css_class("card");
        this.signature_preview.content_loaded.connect(() => {
                // Only enable editability after the content has fully
                // loaded to avoid the WebProcess crashing.
                this.signature_preview.set_editable.begin(
                    true, this.op_cancellable
                );
            });
        this.signature_preview.document_modified.connect(() => {
                this.signature_changed = true;
            });
        var focus_controller = new Gtk.EventControllerFocus();
        focus_controller.leave.connect(() => {
            // This event will also be fired if the top-level
            // window loses focus, e.g. if the user alt-tabs away,
            // so don't execute the command if the signature web
            // view no longer the focus widget
            if (!this.signature_preview.is_focus() &&
                this.signature_changed) {
                this.commands.execute.begin(
                    new SignatureChangedCommand(
                        this.signature_preview, account
                    ),
                    this.op_cancellable
                );
            }
        });
        this.signature_preview.add_controller(focus_controller);

        this.signature_bin.add(this.signature_preview);

        this.signature_preview.load_html(
            Geary.HTML.smart_escape(account.signature)
        );

        this.remove_button.set_visible(
            !this.editor.accounts.is_goa_account(account)
        );

        connect_account_signals();
        connect_command_signals();
    }

    ~EditorEditPane() {
        disconnect_account_signals();
        disconnect_command_signals();
    }

    private void update_display_name() {
        this.display_name_row.text = this.account.display_name;
    }

    internal string? get_default_name() {
        string? name = this.account.primary_mailbox.name;

        if (Geary.String.is_empty_or_whitespace(name)) {
            name = this.editor.accounts.get_account_name();
        }

        return name;
    }

    internal MailboxRow new_mailbox_row(Geary.RFC822.MailboxAddress sender) {
        MailboxRow row = new MailboxRow(this.account, sender, this);
        //XXX GTK4
        // row.move_to.connect(on_sender_row_moved);
        // row.dropped.connect(on_sender_row_dropped);
        return row;
    }

    /** {@inheritDoc} */
    protected void command_executed() {
        this.editor.update_command_actions();

        Application.Command next_undo = this.commands.peek_undo();
        this.undo_button.set_tooltip_text(
            (next_undo != null && next_undo.undo_label != null)
            ? next_undo.undo_label : _("Undo")
        );

        // Ensure the account is notified that is has changed. This
        // might not be 100% correct, but it's close enough.
        this.account.changed();
    }

    private void on_sender_row_moved(EditorRow source, int new_position) {
        this.commands.execute.begin(
            new ReorderMailboxCommand(
                (MailboxRow) source,
                new_position,
                this.account,
                this.senders_list
            ),
            this.op_cancellable
        );
    }

    private void on_sender_row_dropped(EditorRow source, EditorRow target) {
        this.commands.execute.begin(
            new ReorderMailboxCommand(
                (MailboxRow) source,
                target.get_index(),
                this.account,
                this.senders_list
            ),
            this.op_cancellable
        );
    }

    [GtkCallback]
    private void on_server_settings_clicked() {
        this.editor.push_pane(new EditorServersPane(this.editor, this.account));
    }

    [GtkCallback]
    private void on_remove_account_clicked() {
        if (!this.editor.accounts.is_goa_account(account)) {
            var dialog = new Adw.AlertDialog(
                _("Remove Account: %s").printf(account.primary_mailbox.address),
                _("This will remove it from Geary and delete locally cached email data from your computer. Nothing will be deleted from your service provider.")
            );
            dialog.add_css_class("warning");

            dialog.add_response("cancel", _("_Cancel"));
            dialog.close_response = "cancel";
            dialog.add_response("remove", _("_Remove Account"));
            dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE);

            dialog.choose.begin(this, null, (obj, res) => {
                string response = dialog.choose.end(res);
                if (response == "remove")
                    this.editor.remove_account(this.account);
            });
        }
    }

    [GtkCallback]
    private void on_add_mailbox_clicked(Gtk.Button add_button) {
        var dialog = new MailboxEditorDialog.for_new(get_default_name());
        dialog.apply.connect((dialog, mailbox) => {
            this.commands.execute.begin(
                new AppendMailboxCommand(
                    this.senders_list,
                    new_mailbox_row(mailbox)
                ),
                this.op_cancellable
            );
            dialog.close();
        });

        dialog.present(this);
    }

    [GtkCallback]
    private static string period_to_string(Adw.EnumListItem item,
                                           Accounts.PrefetchPeriod period) {
        return period.to_string();
    }
}


/**
 * An enum to describe the possible values for the "Download Mail" option
 */
public enum Accounts.PrefetchPeriod {

    2_WEEKS = 14,
    1_MONTH = 30,
    3_MONTHS = 90,
    6_MONTHS = 180,
    1_YEAR = 365,
    2_YEARS = 720,
    4_YEARS = 1461,
    EVERYTHING = -1;

    public unowned string to_string() {
        switch (this) {
        case 2_WEEKS:
            return _("2 weeks back");
        case 1_MONTH:
            return _("1 month back");
        case 3_MONTHS:
            return _("3 months back");
        case 6_MONTHS:
            return _("6 months back");
        case 1_YEAR:
            return _("1 year back");
        case 2_YEARS:
            return _("2 years back");
        case 4_YEARS:
            return _("4 years back");
        case EVERYTHING:
            return _("Everything");
        }

        return_val_if_reached("");
    }
}

private class Accounts.DisplayNameRow : AccountRow<EditorEditPane,Gtk.Entry> {


    private Components.EntryUndo value_undo;
    private Application.CommandStack commands;
    private GLib.Cancellable? cancellable;


    public DisplayNameRow(Geary.AccountInformation account,
                          Application.CommandStack commands,
                          GLib.Cancellable? cancellable) {
        base(
            account,
            // Translators: Label in the account editor for the user's
            // custom name for an account.
            _("Account name"),
            new Gtk.Entry()
        );
        this.activatable = false;
        this.commands = commands;
        this.cancellable = cancellable;

        update();

        // Hook up after updating the value so the default value isn't
        // undoable
        this.value_undo = new Components.EntryUndo(this.value);

        var focus_controller = new Gtk.EventControllerFocus();
        focus_controller.leave.connect(on_focus_out);
        this.value.add_controller(focus_controller);
    }

    public override void update() {
        this.value.placeholder_text = this.account.primary_mailbox.address;
        // Only update if changed to avoid adding more undo edits
        if (this.value.text != this.account.display_name) {
            this.value.text = this.account.display_name;
        }
    }

    private void commit() {
        string value = this.value.text.strip();
        if (value == "") {
            value = this.account.primary_mailbox.address;
            this.value.text = this.account.primary_mailbox.address;
        }

        if (value != this.account.display_name) {
            this.commands.execute.begin(
                new Application.PropertyCommand<string?>(
                    this.account,
                    "label",
                    value,
                    // Translators: Tooltip used to undo changing
                    // the name of an account. The string
                    // substitution is the old name of the
                    // account.
                    _("Change account name back to “%s”")
                ),
                this.cancellable
            );
        }

        if (Geary.String.is_empty(value)) {
        }
    }

    private void on_focus_out() {
        commit();
    }

}


private class Accounts.MailboxRow : Adw.ActionRow {

    public Geary.AccountInformation account { get; construct set; }

    public Geary.RFC822.MailboxAddress mailbox { get; construct set; }

    public unowned Accounts.EditorEditPane pane { get; construct set; }


    public MailboxRow(Geary.AccountInformation account,
                      Geary.RFC822.MailboxAddress mailbox,
                      Accounts.EditorEditPane pane) {
        Object(
            account: account,
            mailbox: mailbox,
            pane: pane,
            activatable: true
        );

        //XXX GTK4 do this again
        // enable_drag();

        //XXX GTK4 also on notify
        update();
    }

    public override void activate() {
        var dialog = new MailboxEditorDialog.for_existing(
            this.mailbox,
            this.account.has_sender_aliases
        );

        dialog.apply.connect((dialog, mailbox) => {
            this.pane.commands.execute.begin(
                new UpdateMailboxCommand(this, mailbox),
                this.pane.op_cancellable
            );
            dialog.close();
        });

        dialog.remove.connect((dialog) => {
            this.pane.commands.execute.begin(
                new RemoveMailboxCommand(this),
                this.pane.op_cancellable
            );
            dialog.close();
        });

        dialog.present(this);
    }

    private void update() {
        this.title = mailbox.address.strip();

        string? name = this.mailbox.name;
        if (Geary.String.is_empty_or_whitespace(name)) {
            // Translators: Label used to indicate the user has
            // provided no display name for one of their sender
            // email addresses in their account settings.
            name = _("Name not set");
        }
        this.subtitle = name;
    }

}


internal class Accounts.AppendMailboxCommand : Application.Command {


    private Gtk.ListBox senders_list;
    private MailboxRow new_row = null;

    private int mailbox_index;


    public AppendMailboxCommand(Gtk.ListBox senders_list, MailboxRow new_row) {
        this.senders_list = senders_list;
        this.new_row = new_row;

        this.mailbox_index = new_row.account.sender_mailboxes.size;

        // Translators: Label used as the undo tooltip after adding an
        // new sender email address to an account. The string
        // substitution is the email address added.
        this.undo_label = _("Remove “%s”").printf(new_row.mailbox.address);
    }

    public async override void execute(GLib.Cancellable? cancellable) {
        this.senders_list.insert(this.new_row, this.mailbox_index);
        this.new_row.account.append_sender(this.new_row.mailbox);
        this.new_row.account.changed();
    }

    public async override void undo(GLib.Cancellable? cancellable) {
        this.senders_list.remove(this.new_row);
        this.new_row.account.remove_sender(this.new_row.mailbox);
        this.new_row.account.changed();
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
            row.account.sender_mailboxes.index_of(this.old_mailbox);

        // Translators: Label used as the undo tooltip after editing a
        // sender address for an account. The string substitution is
        // the email address edited.
        this.undo_label = _("Undo changes to “%s”").printf(
            this.old_mailbox.address
        );
    }

    public async override void execute(GLib.Cancellable? cancellable) {
        this.row.mailbox = this.new_mailbox;
        this.row.account.replace_sender(this.mailbox_index, this.new_mailbox);
        this.row.account.changed();
    }

    public async override void undo(GLib.Cancellable? cancellable) {
        this.row.mailbox = this.old_mailbox;
        this.row.account.replace_sender(this.mailbox_index, this.old_mailbox);
        this.row.account.changed();
    }

}


internal class Accounts.ReorderMailboxCommand : Application.Command {


    private MailboxRow source;
    private int source_index;
    private int target_index;

    private Geary.AccountInformation account;
    private Gtk.ListBox list;


    public ReorderMailboxCommand(MailboxRow source,
                                 int target_index,
                                 Geary.AccountInformation account,
                                 Gtk.ListBox list) {
        this.source = source;
        this.source_index = source.get_index();
        this.target_index = target_index;

        this.account = account;
        this.list = list;
    }

    public async override void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        move_source(this.target_index);
    }

    public async override void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        move_source(this.source_index);
    }

    private void move_source(int destination) {
        this.account.remove_sender(this.source.mailbox);
        this.account.insert_sender(destination, this.source.mailbox);

        this.list.remove(this.source);
        this.list.insert(this.source, destination);

        this.source.grab_focus();
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
            row.account.sender_mailboxes.index_of(mailbox);
        this.list = (Gtk.ListBox) row.get_parent();

        // Translators: Label used as the undo tooltip after removing
        // a sender address from an account. The string substitution
        // is the email address edited.
        this.undo_label = _("Add “%s” back").printf(this.mailbox.address);
    }

    public async override void execute(GLib.Cancellable? cancellable) {
        this.list.remove(this.row);
        this.row.account.remove_sender(this.mailbox);
        this.row.account.changed();
    }

    public async override void undo(GLib.Cancellable? cancellable) {
        this.list.insert(this.row, this.mailbox_index);
        this.row.account.insert_sender(this.mailbox_index, this.mailbox);
        this.row.account.changed();
    }

}


internal class Accounts.SignatureChangedCommand : Application.Command {


    private Components.WebView signature_view;
    private Geary.AccountInformation account;

    private string old_value;
    private bool old_enabled;

    private string? new_value = null;
    private bool new_enabled = false;


    public SignatureChangedCommand(Components.WebView signature_view,
                                   Geary.AccountInformation account) {
        this.signature_view = signature_view;
        this.account = account;

        this.old_value = Geary.HTML.smart_escape(account.signature);
        this.old_enabled = account.use_signature;

        // Translators: Label used as the undo tooltip after removing
        // a sender address from an account. The string substitution
        // is the email address edited.
        this.undo_label = _("Undo signature changes");
    }

    public async override void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.new_value = yield this.signature_view.get_html();
        this.new_enabled = !Geary.String.is_empty_or_whitespace(
            Geary.HTML.html_to_text(this.new_value)
        );
        update_account_signature(this.new_value, this.new_enabled);
    }

    public async override void undo(GLib.Cancellable? cancellable) {
        this.signature_view.load_html(this.old_value);
        update_account_signature(this.old_value, this.old_enabled);
    }

    public async override void redo(GLib.Cancellable? cancellable) {
        this.signature_view.load_html(this.new_value);
        update_account_signature(this.new_value, this.new_enabled);
    }

    private inline void update_account_signature(string sig, bool enabled) {
        this.account.signature = sig;
        this.account.use_signature = enabled;
        this.account.changed();
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
                    new Application.PropertyCommand<int>(
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
                    pane.op_cancellable
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
