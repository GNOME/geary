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

    // These are copies of the originals that can be updated before
    // validating on apply, without breaking anything.
    private Geary.ServiceInformation imap_mutable;
    private Geary.ServiceInformation smtp_mutable;


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

    private ServiceSmtpAuthRow smtp_auth;
    private ServiceLoginRow smtp_login;


    public EditorServersPane(Editor editor, Geary.AccountInformation account) {
        this.editor = editor;
        this.account = account;

        this.pane_content.set_focus_vadjustment(this.pane_adjustment);

        this.imap_mutable = account.imap.temp_copy();
        this.smtp_mutable = account.smtp.temp_copy();

        this.details_list.set_header_func(Editor.seperator_headers);
        // Only add an account provider if it is esoteric enough.
        if (this.account.imap.mediator is GoaMediator) {
            this.details_list.add(
                new AccountProviderRow(editor.accounts, this.account)
            );
        }
        ServiceProviderRow<EditorServersPane> service_provider =
            new ServiceProviderRow<EditorServersPane>(
                this.account.service_provider,
                this.account.service_label
            );
        service_provider.set_dim_label(true);
        service_provider.activatable = false;
        this.details_list.add(service_provider);
        this.details_list.add(new SaveDraftsRow(this.account));

        this.receiving_list.set_header_func(Editor.seperator_headers);
        this.receiving_list.add(new ServiceHostRow(account, account.imap));
        this.receiving_list.add(new ServiceSecurityRow(account, account.imap));
        this.receiving_list.add(new ServiceLoginRow(account, account.imap));

        this.sending_list.set_header_func(Editor.seperator_headers);
        this.sending_list.add(new ServiceHostRow(account, account.smtp));
        this.sending_list.add(new ServiceSecurityRow(account, account.smtp));
        this.smtp_auth = new ServiceSmtpAuthRow(account, account.smtp);
        this.smtp_auth.value.changed.connect(on_smtp_auth_changed);
        this.sending_list.add(this.smtp_auth);
        this.smtp_login = new ServiceLoginRow(account, account.smtp);
        this.sending_list.add(this.smtp_login);

        this.account.information_changed.connect(on_account_changed);

        update_header();
        update_smtp_auth();
    }

    ~EditorServersPane() {
        this.account.information_changed.disconnect(on_account_changed);
    }

    internal Gtk.HeaderBar get_header() {
        return this.header;
    }

    private void update_smtp_auth() {
        this.smtp_login.set_visible(
            this.smtp_auth.value.source == Geary.SmtpCredentials.CUSTOM
        );
        this.smtp_login.update();
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

    private void on_smtp_auth_changed() {
        update_smtp_auth();
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
        set_activatable(false);

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

    public override void activated(EditorServersPane pane) {
        EditorPopover popover = new EditorPopover();

        string? value = this.service.host;
        Gtk.Entry entry = new Gtk.Entry();
        entry.set_text(value ?? "");
        entry.set_placeholder_text(value ?? "");
        entry.set_width_chars(20);
        entry.show();

        popover.set_relative_to(this.value);
        popover.layout.add(entry);
        popover.popup();
    }

    public override void update() {
        string value = this.service.host;
        if (Geary.String.is_empty(value)) {
            value = _("None");
        }

        // Only show the port if it not the appropriate default port
        bool custom_port = false;
        int port = this.service.port;
        Geary.TlsNegotiationMethod security = this.service.transport_security;
        switch (this.service.protocol) {
        case Geary.Protocol.IMAP:
            if (!(port == Geary.Imap.ClientConnection.IMAP_PORT &&
                  (security == Geary.TlsNegotiationMethod.NONE ||
                   security == Geary.TlsNegotiationMethod.START_TLS)) &&
                !(port == Geary.Imap.ClientConnection.IMAP_TLS_PORT &&
                  security == Geary.TlsNegotiationMethod.TRANSPORT)) {
                custom_port = true;
            }
            break;
        case Geary.Protocol.SMTP:
            if (!(port == Geary.Smtp.ClientConnection.SMTP_PORT &&
                  (security == Geary.TlsNegotiationMethod.NONE ||
                   security == Geary.TlsNegotiationMethod.START_TLS)) &&
                !(port == Geary.Smtp.ClientConnection.SUBMISSION_PORT &&
                  (security == Geary.TlsNegotiationMethod.NONE ||
                   security == Geary.TlsNegotiationMethod.START_TLS)) &&
                !(port == Geary.Smtp.ClientConnection.SUBMISSION_TLS_PORT &&
                  security == Geary.TlsNegotiationMethod.TRANSPORT)) {
                custom_port = true;
            }
            break;
        }
        if (custom_port) {
            value = "%s:%d".printf(value, this.service.port);
        }

        this.value.set_text(value);
    }

}


private class Accounts.ServiceSecurityRow :
    ServiceRow<EditorServersPane,TlsComboBox> {

    public ServiceSecurityRow(Geary.AccountInformation account,
                              Geary.ServiceInformation service) {
        TlsComboBox value = new TlsComboBox();
        base(account, service, value.label, value);
        update();
        value.changed.connect(on_value_changed);
    }

    public override void update() {
        this.value.method = this.service.transport_security;
    }

    private void on_value_changed() {
        this.service.transport_security = this.value.method;
    }

}


private class Accounts.ServiceLoginRow :
    ServiceRow<EditorServersPane,Gtk.Label> {

    public ServiceLoginRow(Geary.AccountInformation account,
                           Geary.ServiceInformation service) {
        base(
            account,
            service,
            // Translators: This label describes the authentication
            // scheme used by an account's IMAP or SMTP service.
            _("Login name"),
            new Gtk.Label("")
        );

        this.value.ellipsize = Pango.EllipsizeMode.MIDDLE;
        update();
    }

    public override void activated(EditorServersPane pane) {
        EditorPopover popover = new EditorPopover();

        string? value = null;
        if (this.service.credentials != null) {
            value = this.service.credentials.user;
        }
        Gtk.Entry entry = new Gtk.Entry();
        entry.set_text(value ?? "");
        entry.set_placeholder_text(value ?? "");
        entry.set_width_chars(20);
        entry.show();

        popover.set_relative_to(this.value);
        popover.layout.add(entry);
        popover.popup();
    }

    public override void update() {
        string? label = null;
        if (this.service.credentials != null) {
            string method = "%s";
            Gtk.StyleContext value_style = this.value.get_style_context();
            switch (this.service.credentials.supported_method) {
            case Geary.Credentials.Method.PASSWORD:
                this.activatable = true;
                value_style.remove_class(Gtk.STYLE_CLASS_DIM_LABEL);
                break;

            case Geary.Credentials.Method.OAUTH2:
                // Add a suffix for OAuth2 auth so people know they
                // shouldn't expect to be prompted for a password

                // Translators: Label used when an account's IMAP or
                // SMTP service uses OAuth2. The string replacement is
                // the service's login name.
                method = _("%s using OAuth2");

                this.activatable = false;
                value_style.add_class(Gtk.STYLE_CLASS_DIM_LABEL);
                break;
            }

            string? login = this.service.credentials.user;
            if (Geary.String.is_empty(login)) {
                login = _("Unknown");
            }

            label = method.printf(login);
        } else if (this.service.protocol == Geary.Protocol.SMTP &&
                   this.service.smtp_use_imap_credentials) {
            label = _("Use IMAP login");
        } else {
            // Translators: Label used when no auth scheme is used
            // by an account's IMAP or SMTP service.
            label = _("None");
        }
        this.value.set_text(label);
    }

}

private class Accounts.ServiceSmtpAuthRow :
    ServiceRow<EditorServersPane,SmtpAuthComboBox> {

    public ServiceSmtpAuthRow(Geary.AccountInformation account,
                              Geary.ServiceInformation service) {
        SmtpAuthComboBox value = new SmtpAuthComboBox();
        base(account, service, value.label, value);
        this.activatable = false;
        update();
        value.changed.connect(on_value_changed);
    }

    public override void update() {
        this.value.source = this.service.smtp_credentials_source;
    }

    private void on_value_changed() {
        this.service.smtp_credentials_source = this.value.source;
    }

}
