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
        this.details_list.add(new EmailPrefetchRow(this.account));
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


private abstract class Accounts.ServerAccountRow<V> : LabelledEditorRow {


    protected Geary.AccountInformation account;

    protected V value;


    public ServerAccountRow(Geary.AccountInformation account,
                            string label,
                            V value) {
        base(label);
        this.account = account;

        set_dim_label(true);

        this.value = value;

        Gtk.Widget? widget = value as Gtk.Widget;
        if (widget != null) {
            widget.valign = Gtk.Align.CENTER;
            widget.show();
            this.layout.add(widget);
        }
    }

    public abstract void update();

}


private class Accounts.ServiceProviderRow : ServerAccountRow<Gtk.Label> {


    public ServiceProviderRow(Geary.AccountInformation account) {
        base(
            account,
            // Translators: This label describes service hosting the
            // email account, e.g. GMail, Yahoo, Outlook.com, or some
            // other generic IMAP service.
            _("Service provider"),
            new Gtk.Label("")
        );

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
        // Can't change this, so dim it out
        this.value.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
    }

}


private class Accounts.AccountProviderRow : ServerAccountRow<Gtk.Label> {


    public AccountProviderRow(Geary.AccountInformation account) {
        base(
            account,
            // Translators: This label describes the program that
            // created the account, e.g. an SSO service like GOA, or
            // locally by Geary.
            _("Account source"),
            new Gtk.Label("")
        );

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
        // Can't change this, so dim it out
        this.value.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
    }

}


private class Accounts.SaveDraftsRow : ServerAccountRow<Gtk.Switch> {


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


private class Accounts.EmailPrefetchRow : ServerAccountRow<Gtk.ComboBoxText> {


    private static bool row_separator(Gtk.TreeModel model, Gtk.TreeIter iter) {
        GLib.Value v;
        model.get_value(iter, 0, out v);
        return v.get_string() == ".";
    }


    public EmailPrefetchRow(Geary.AccountInformation account) {
        Gtk.ComboBoxText combo = new Gtk.ComboBoxText();
        combo.set_row_separator_func(row_separator);
        combo.append("14", _("2 weeks back")); // IDs are # of days
        combo.append("30", _("1 month back"));
        combo.append("90", _("3 months back"));
        combo.append("180", _("6 months back"));
        combo.append("365", _("1 year back"));
        combo.append("730", _("2 years back"));
        combo.append("1461", _("4 years back"));
        combo.append(".", "."); // Separator
        combo.append("-1", _("Everything"));

        base(
            account,
            // Translators: This label describes the account
            // preference for the length of time (weeks, months or
            // years) that past email should be downloaded.
            _("Download mail"),
            combo
        );

        update();
    }

    public override void update() {
        this.value.set_active_id(this.account.prefetch_period_days.to_string());
    }

}


private abstract class Accounts.ServerServiceRow<V> : ServerAccountRow<V> {


    protected Geary.ServiceInformation service;

    public virtual bool is_value_editable {
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


    public ServerServiceRow(Geary.AccountInformation account,
                            Geary.ServiceInformation service,
                            string label,
                            V value) {
        base(account, label, value);
        this.service = service;

        Gtk.Widget? widget = value as Gtk.Widget;
        if (widget != null && !this.is_value_editable) {
            if (widget is Gtk.Label) {
                widget.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
            } else {
                widget.set_sensitive(false);
            }
        }
    }

}


private class Accounts.ServiceHostRow : ServerServiceRow<Gtk.Label> {

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
    ServerServiceRow<Gtk.ComboBoxText> {

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


private class Accounts.ServiceAuthRow : ServerServiceRow<Gtk.Label> {

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
