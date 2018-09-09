/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An account editor pane for editing server details for an account.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_servers_pane.ui")]
internal class Accounts.EditorServersPane : Gtk.Grid, EditorPane, AccountPane {


    internal Geary.AccountInformation account { get ; protected set; }

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
    private Gtk.ListBox receiving_list;

    [GtkChild]
    private Gtk.ListBox sending_list;


    public EditorServersPane(Editor editor, Geary.AccountInformation account) {
        this.editor = editor;
        this.account = account;

        this.pane_content.set_focus_vadjustment(this.pane_adjustment);

        this.details_list.set_header_func(Editor.seperator_headers);
        this.details_list.add(
            new ServiceProviderRow<EditorServersPane>(
                this.account.service_provider,
                this.account.service_label
            )
        );
        // Only add an account provider if it is esoteric enough.
        if (this.account.imap.mediator is GoaMediator) {
            this.details_list.add(
                new AccountProviderRow(editor.accounts, this.account)
            );
        }
        this.details_list.add(new SaveDraftsRow(this.account));

        this.receiving_list.set_header_func(Editor.seperator_headers);
        build_service(account.imap, this.receiving_list);

        this.sending_list.set_header_func(Editor.seperator_headers);
        build_service(account.smtp, this.sending_list);

        this.account.information_changed.connect(on_account_changed);
        update_header();
    }

    ~EditorServersPane() {
        this.account.information_changed.disconnect(on_account_changed);
    }

    internal Gtk.HeaderBar get_header() {
        return this.header;
    }

    private void build_service(Geary.ServiceInformation service,
                               Gtk.ListBox settings_list) {
        settings_list.add(new ServiceHostRow(this.account, service));
        settings_list.add(new ServiceSecurityRow(this.account, service));
        settings_list.add(new ServiceAuthRow(this.account, service));
    }

    [GtkCallback]
    private void on_cancel_button_clicked() {
        this.editor.pop();
    }

    [GtkCallback]
    private void on_apply_button_clicked() {
    }

    [GtkCallback]
    private bool on_list_keynav_failed(Gtk.Widget widget,
                                       Gtk.DirectionType direction) {
        bool ret = Gdk.EVENT_PROPAGATE;
        Gtk.Container? next = null;
        if (direction == Gtk.DirectionType.DOWN) {
            if (widget == this.details_list) {
                next = this.receiving_list;
            } else if (widget == this.receiving_list) {
                next = this.sending_list;
            }
        } else if (direction == Gtk.DirectionType.UP) {
            if (widget == this.sending_list) {
                next = this.receiving_list;
            } else if (widget == this.receiving_list) {
                next = this.details_list;
            }
        }

        if (next != null) {
            next.child_focus(direction);
            ret = Gdk.EVENT_STOP;
        }
        return ret;
    }

    private void on_account_changed() {
        update_header();
    }

    [GtkCallback]
    private void on_activate(Gtk.ListBoxRow row) {
        Accounts.EditorRow<EditorServersPane> server_row =
            row as Accounts.EditorRow<EditorServersPane>;
        if (server_row != null) {
            server_row.activated(this);
        }
    }

}


private class Accounts.AccountProviderRow :
    AccountRow<EditorServersPane,Gtk.Label> {

    private Manager accounts;

    public AccountProviderRow(Manager accounts,
                              Geary.AccountInformation account) {
        base(
            account,
            // Translators: This label describes the program that
            // created the account, e.g. an SSO service like GOA, or
            // locally by Geary.
            _("Account source"),
            new Gtk.Label("")
        );

        this.accounts = accounts;

        update();
    }

    public override void update() {
        string? source = null;
        bool enabled = false;
        if (this.account.imap.mediator is GoaMediator) {
            source = _("GNOME Online Accounts");
            enabled = true;
        } else {
            source = _("Geary");
        }

        this.value.set_text(source);
        this.set_activatable(enabled);
        Gtk.StyleContext style = this.value.get_style_context();
        if (enabled) {
            style.remove_class(Gtk.STYLE_CLASS_DIM_LABEL);
        } else {
            style.add_class(Gtk.STYLE_CLASS_DIM_LABEL);
        }
    }

    public override void activated(EditorServersPane pane) {
        if (this.accounts.is_goa_account(this.account)) {
            this.accounts.show_goa_account.begin(
                account, null,
                (obj, res) => {
                    try {
                        this.accounts.show_goa_account.end(res);
                    } catch (GLib.Error err) {
                        // XXX display an error to the user
                        debug(
                            "Failed to show GOA account \"%s\": %s",
                            account.id,
                            err.message
                        );
                    }
                });
        }
    }

}


private class Accounts.SaveDraftsRow :
    AccountRow<EditorServersPane,Gtk.Switch> {


    public SaveDraftsRow(Geary.AccountInformation account) {
        base(
            account,
            // Translators: This label describes an account
            // preference.
            _("Save drafts on server"),
            new Gtk.Switch()
        );

        update();
    }

    public override void update() {
        this.value.state = this.account.save_drafts;
    }

}


private class Accounts.ServiceHostRow :
    ServiceRow<EditorServersPane,Gtk.Label> {

    public ServiceHostRow(Geary.AccountInformation account,
                          Geary.ServiceInformation service) {
        string label = _("Unknown");
        switch (service.protocol) {
        case Geary.Protocol.IMAP:
            // Translators: This label describes the host name or IP
            // address and port used by an account's IMAP service.
            label = _("IMAP server");
            break;

        case Geary.Protocol.SMTP:
            // Translators: This label describes the host name or IP
            // address and port used by an account's SMTP service.
            label = _("SMTP server");
            break;
        }

        base(
            account,
            service,
            label,
            new Gtk.Label("")
        );

        update();
    }

    public override void update() {
        this.value.set_text(
            Geary.String.is_empty(this.service.host)
                ? _("None")
                : "%s:%d".printf(this.service.host, this.service.port)
        );
    }

}


private class Accounts.ServiceSecurityRow :
    ServiceRow<EditorServersPane,TlsComboBox> {

    public ServiceSecurityRow(Geary.AccountInformation account,
                              Geary.ServiceInformation service) {
        TlsComboBox value = new TlsComboBox();
        base(account, service, value.label, value);
        update();
    }

    public override void update() {
        if (this.service.use_ssl) {
            this.value.method = Geary.TlsNegotiationMethod.TRANSPORT;
        } else if (this.service.use_starttls) {
            this.value.method = Geary.TlsNegotiationMethod.START_TLS;
        } else {
            this.value.method = Geary.TlsNegotiationMethod.NONE;
        }
    }

}


private class Accounts.ServiceAuthRow :
    ServiceRow<EditorServersPane,Gtk.Label> {

    public ServiceAuthRow(Geary.AccountInformation account,
                          Geary.ServiceInformation service) {
        base(
            account,
            service,
            // Translators: This label describes the authentication
            // scheme used by an account's IMAP or SMTP service.
            _("Login"),
            new Gtk.Label("")
        );

        update();
    }

    public override void update() {
        string? label = null;
        if (this.service.credentials != null) {
            string method = _("Unknown");
            switch (this.service.credentials.supported_method) {
            case Geary.Credentials.Method.PASSWORD:
                // Translators: This is used when an account's IMAP or
                // SMTP service uses password auth. The string
                // replacement is the service's login name.
                method = _("%s with password");
                break;

            case Geary.Credentials.Method.OAUTH2:
                // Translators: This is used when an account's IMAP or
                // SMTP service uses OAuth2. The string replacement is
                // the service's login name.
                method = _("%s via OAuth2");
                break;
            }

            string? login = this.service.credentials.user;
            if (Geary.String.is_empty(login)) {
                login = _("Unknown");
            }

            label = method.printf(login);
        } else if (this.service.protocol == Geary.Protocol.SMTP &&
                   this.service.smtp_use_imap_credentials) {
            label = _("Use IMAP server login");
        } else {
            // Translators: This is used when no auth scheme is used
            // by an account's IMAP or SMTP service.
            label = _("None");
        }
        this.value.set_text(label);
    }

}
