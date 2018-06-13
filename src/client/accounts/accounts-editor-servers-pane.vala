/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The main account editor window.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_servers_pane.ui")]
public class Accounts.EditorServersPane : Gtk.Grid {


    private weak Editor editor; // circular ref
    private Geary.AccountInformation account;

    [GtkChild]
    private Gtk.ListBox details_list;

    [GtkChild]
    private Gtk.ListBox receiving_list;

    [GtkChild]
    private Gtk.ListBox sending_list;


    public EditorServersPane(Editor editor, Geary.AccountInformation account) {
        this.editor = editor;
        this.account = account;

        this.details_list.set_header_func(Editor.seperator_headers);
        this.details_list.add(new ServiceProviderRow(this.account));
        // Only add an account provider if it is esoteric enough.
        if (this.account.imap.mediator is GoaMediator) {
            this.details_list.add(new AccountProviderRow(this.account));
        }
        this.details_list.add(new SaveDraftsRow(this.account));

        this.receiving_list.set_header_func(Editor.seperator_headers);
        build_service(account.imap, this.receiving_list);

        this.sending_list.set_header_func(Editor.seperator_headers);
        build_service(account.smtp, this.sending_list);
    }

    private void build_service(Geary.ServiceInformation service,
                               Gtk.ListBox settings_list) {
        settings_list.add(new ServiceHostRow(this.account, service));
        settings_list.add(new ServiceSecurityRow(this.account, service));
        settings_list.add(new ServiceAuthRow(this.account, service));
    }

}


private class Accounts.ServiceProviderRow : AccountRow<Gtk.Label> {


    public ServiceProviderRow(Geary.AccountInformation account) {
        base(
            account,
            // Translators: This label describes service hosting the
            // email account, e.g. GMail, Yahoo, Outlook.com, or some
            // other generic IMAP service.
            _("Service provider"),
            new Gtk.Label("")
        );

        // Can't change this, so dim it out
        this.value.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
        set_activatable(false);

        update();
    }

    public override void update() {
        string? details = this.account.service_label;
        switch (this.account.service_provider) {
        case Geary.ServiceProvider.GMAIL:
            details = _("GMail");
            break;

        case Geary.ServiceProvider.OUTLOOK:
            details = _("Outlook.com");
            break;

        case Geary.ServiceProvider.YAHOO:
            details = _("Yahoo");
            break;
        }
        this.value.set_text(details);
    }

}


private class Accounts.AccountProviderRow : AccountRow<Gtk.Label> {


    public AccountProviderRow(Geary.AccountInformation account) {
        base(
            account,
            // Translators: This label describes the program that
            // created the account, e.g. an SSO service like GOA, or
            // locally by Geary.
            _("Account source"),
            new Gtk.Label("")
        );

        // Can't change this, so dim it out
        this.value.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
        this.set_activatable(false);

        update();
    }

    public override void update() {
        string? source = null;
        if (this.account.imap.mediator is GoaMediator) {
            source = _("GNOME Online Accounts");
        } else {
            source = _("Geary");
        }
        this.value.set_text(source);
    }

}


private class Accounts.SaveDraftsRow : AccountRow<Gtk.Switch> {


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


private class Accounts.ServiceHostRow : ServiceRow<Gtk.Label> {

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


private class Accounts.ServiceSecurityRow : ServiceRow<Gtk.ComboBoxText> {

    private const string INSECURE_ICON = "channel-insecure-symbolic";
    private const string SECURE_ICON = "channel-secure-symbolic";

    public ServiceSecurityRow(Geary.AccountInformation account,
                              Geary.ServiceInformation service) {
        Gtk.ListStore store = new Gtk.ListStore(
            3, typeof(string), typeof(string), typeof(string)
        );
		Gtk.TreeIter iter;
		store.append(out iter);
		store.set(iter, 0, "none", 1, INSECURE_ICON, 2, _("None"));
		store.append(out iter);
		store.set(iter, 0, "start-tls", 1, SECURE_ICON, 2, _("StartTLS"));
		store.append(out iter);
		store.set(iter, 0, "tls", 1, SECURE_ICON, 2, _("TLS"));

        Gtk.ComboBox combo = new Gtk.ComboBox.with_model(store);
        combo.set_id_column(0);

        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText();
		combo.pack_start(text_renderer, true);
		combo.add_attribute(text_renderer, "text", 2);

        Gtk.CellRendererPixbuf icon_renderer = new Gtk.CellRendererPixbuf();
		combo.pack_start(icon_renderer, true);
		combo.add_attribute(icon_renderer, "icon_name", 1);

        base(
            account,
            service,
            // Translators: This label describes what form of secure
            // connection (TLS, StartTLS, etc) used by an account's
            // IMAP or SMTP service.
            _("Transport security"),
            combo
        );

        update();
    }

    public override void update() {
        if (this.service.use_ssl) {
            this.value.set_active_id("tls");
        } else if (this.service.use_starttls) {
            this.value.set_active_id("start-tls");
        } else {
            this.value.set_active_id("none");
        }
    }

}


private class Accounts.ServiceAuthRow : ServiceRow<Gtk.Label> {

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
