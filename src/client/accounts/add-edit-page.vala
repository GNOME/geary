/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Page for adding or editing an account.
public class AddEditPage : Gtk.Box {
    /// Placeholder text indicating that the user should type their first name and last name
    private const string REAL_NAME_PLACEHOLDER = _("First Last");
    
    public enum PageMode {
        WELCOME,
        ADD,
        EDIT
    }
    
    public string real_name {
        get { return entry_real_name.text; }
        set { entry_real_name.text = value; }
    }
    
    public string nickname {
        get { return (mode == PageMode.WELCOME) ? email_address : entry_nickname.text; }
        set { entry_nickname.text = value; }
    }
    
    public string email_address {
        get { return entry_email.text; }
        set { entry_email.text = value; }
    }
    
    public string password {
        get { return entry_password.text; }
        set { entry_password.text = value; }
    }
    
    public string imap_username {
        get { return entry_imap_username.text; }
        set { entry_imap_username.text = value; }
    }
    
    public string imap_password {
        get { return entry_imap_password.text; }
        set { entry_imap_password.text = value; }
    }
    
    public bool remember_password {
        get { return check_remember_password.active; }
        set { check_remember_password.active = value; }
    }
    
    public bool save_sent_mail {
        get { return check_save_sent_mail.active; }
        set { check_save_sent_mail.active = value; }
    }
    
    public string smtp_username {
        get { return entry_smtp_username.text; }
        set { entry_smtp_username.text = value; }
    }
    
    public string smtp_password {
        get { return entry_smtp_password.text; }
        set { entry_smtp_password.text = value; }
    }
    
    public string imap_host {
        get { return entry_imap_host.text; }
        set { entry_imap_host.text = value; }
    }
    
    public uint16 imap_port {
        get { return (uint16) int.parse(entry_imap_port.text.strip()); }
        set { entry_imap_port.text = value.to_string(); }
    }
    
    public bool imap_ssl {
        get { return combo_imap_encryption.active == Encryption.SSL; }
        set {
            if (value)
                combo_imap_encryption.active = Encryption.SSL;
        }
    }
    
    public bool imap_starttls {
        get { return combo_imap_encryption.active == Encryption.STARTTLS; }
        set {
            if (value)
                combo_imap_encryption.active = Encryption.STARTTLS;
        }
    }
    
    public string smtp_host {
        get { return entry_smtp_host.text; }
        set { entry_smtp_host.text = value; }
    }
    
    public uint16 smtp_port {
        get { return (uint16) int.parse(entry_smtp_port.text.strip()); }
        set { entry_smtp_port.text = value.to_string(); }
    }
    
    public bool smtp_ssl {
        get { return combo_smtp_encryption.active == Encryption.SSL; }
        set {
            if (value)
                combo_smtp_encryption.active = Encryption.SSL;
        }
    }
    
    public bool smtp_starttls {
        get { return combo_smtp_encryption.active == Encryption.STARTTLS; }
        set {
            if (value)
                combo_smtp_encryption.active = Encryption.STARTTLS;
        }
    }

    public bool smtp_noauth {
        get { return check_smtp_noauth.active; }
        set { check_smtp_noauth.active = value; }
    }

    // these are tied to the values in the Glade file
    private enum Encryption {
        NONE = 0,
        SSL = 1,
        STARTTLS = 2
    }
    
    private PageMode mode = PageMode.WELCOME;
    
    private Gtk.Widget container_widget;
    private Gtk.Box welcome_box;
    
    private Gtk.Label label_error;
    
    private Gtk.Entry entry_email;
    private Gtk.Label label_password;
    private Gtk.Entry entry_password;
    private Gtk.Entry entry_real_name;
    private Gtk.Label label_nickname;
    private Gtk.Entry entry_nickname;
    private Gtk.ComboBoxText combo_service;
    private Gtk.CheckButton check_remember_password;
    private Gtk.CheckButton check_save_sent_mail;
    
    private Gtk.Alignment other_info;
    
    // IMAP info widgets
    private Gtk.Entry entry_imap_host;
    private Gtk.Entry entry_imap_port;
    private Gtk.Entry entry_imap_username;
    private Gtk.Entry entry_imap_password;
    private Gtk.ComboBox combo_imap_encryption;
    
    // SMTP info widgets
    private Gtk.Entry entry_smtp_host;
    private Gtk.Entry entry_smtp_port;
    private Gtk.Entry entry_smtp_username;
    private Gtk.Entry entry_smtp_password;
    private Gtk.ComboBox combo_smtp_encryption;
    private Gtk.CheckButton check_smtp_noauth;

    private string smtp_username_store;
    private string smtp_password_store;
    
    // Storage options
    private Gtk.Box storage_container;
    private Gtk.ComboBoxText combo_storage_length;
    
    private bool edited_imap_port = false;
    private bool edited_smtp_port = false;
    
    private Geary.Engine.ValidationResult last_validation_result = Geary.Engine.ValidationResult.OK;
    
    private bool first_ui_update = true;
    
    public signal void info_changed();
    
    public signal void size_changed();
    
    public AddEditPage() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 4);
        
        Gtk.Builder builder = GearyApplication.instance.create_builder("login.glade");
        
        // Primary container.
        container_widget = (Gtk.Widget) builder.get_object("container");
        pack_start(container_widget);
        
        welcome_box = (Gtk.Box) builder.get_object("welcome_box");
        Gtk.Label label_welcome = (Gtk.Label) builder.get_object("label-welcome");
        label_welcome.set_markup("<span size=\"large\"><b>%s</b></span>\n%s".printf(
            _("Welcome to Geary."), _("Enter your account information to get started.")));
        
        entry_real_name = (Gtk.Entry) builder.get_object("entry: real_name");
        entry_real_name.placeholder_text = REAL_NAME_PLACEHOLDER;
        label_nickname = (Gtk.Label) builder.get_object("label: nickname");
        entry_nickname = (Gtk.Entry) builder.get_object("entry: nickname");
        combo_service =  (Gtk.ComboBoxText) builder.get_object("combo: service");
        entry_email = (Gtk.Entry) builder.get_object("entry: email");
        label_password = (Gtk.Label) builder.get_object("label: password");
        entry_password = (Gtk.Entry) builder.get_object("entry: password");
        check_remember_password = (Gtk.CheckButton) builder.get_object("check: remember_password");
        check_save_sent_mail = (Gtk.CheckButton) builder.get_object("check: save_sent_mail");
        
        label_error = (Gtk.Label) builder.get_object("label: error");
        
        other_info = (Gtk.Alignment) builder.get_object("container: other_info");
        
        // Storage options.
        storage_container = (Gtk.Box) builder.get_object("storage container");
        combo_storage_length = (Gtk.ComboBoxText) builder.get_object("combo: storage");
        combo_storage_length.set_row_separator_func(combo_storage_separator_delegate);
        combo_storage_length.append("14", _("2 weeks back")); // IDs are # of days
        combo_storage_length.append("30", _("1 month back"));
        combo_storage_length.append("90", _("3 months back"));
        combo_storage_length.append("180", _("6 months back"));
        combo_storage_length.append("365", _("1 year back"));
        combo_storage_length.append(".", "."); // Separator
        combo_storage_length.append("-1", _("Everything"));
        
        // IMAP info widgets.
        entry_imap_host = (Gtk.Entry) builder.get_object("entry: imap host");
        entry_imap_port = (Gtk.Entry) builder.get_object("entry: imap port");
        entry_imap_username = (Gtk.Entry) builder.get_object("entry: imap username");
        entry_imap_password = (Gtk.Entry) builder.get_object("entry: imap password");
        combo_imap_encryption = (Gtk.ComboBox) builder.get_object("combo: imap encryption");
        
        // SMTP info widgets.
        entry_smtp_host = (Gtk.Entry) builder.get_object("entry: smtp host");
        entry_smtp_port = (Gtk.Entry) builder.get_object("entry: smtp port");
        entry_smtp_username = (Gtk.Entry) builder.get_object("entry: smtp username");
        entry_smtp_password = (Gtk.Entry) builder.get_object("entry: smtp password");
        combo_smtp_encryption = (Gtk.ComboBox) builder.get_object("combo: smtp encryption");
        check_smtp_noauth = (Gtk.CheckButton) builder.get_object("check: smtp no authentication");

        // Build list of service providers.
        foreach (Geary.ServiceProvider p in Geary.ServiceProvider.get_providers())
            combo_service.append_text(p.display_name());
        
        reset_all();
        
        combo_service.changed.connect(update_ui);
        entry_email.changed.connect(on_changed);
        entry_password.changed.connect(on_changed);
        entry_real_name.changed.connect(on_changed);
        entry_nickname.changed.connect(on_changed);
        check_remember_password.toggled.connect(on_changed);
        check_save_sent_mail.toggled.connect(on_changed);
        combo_service.changed.connect(on_changed);
        entry_imap_host.changed.connect(on_changed);
        entry_imap_port.changed.connect(on_changed);
        entry_imap_username.changed.connect(on_changed);
        entry_imap_password.changed.connect(on_changed);
        entry_smtp_host.changed.connect(on_changed);
        entry_smtp_port.changed.connect(on_changed);
        entry_smtp_username.changed.connect(on_changed);
        entry_smtp_password.changed.connect(on_changed);
        
        entry_email.changed.connect(on_email_changed);
        entry_password.changed.connect(on_password_changed);
        
        combo_imap_encryption.changed.connect(on_imap_encryption_changed);
        combo_smtp_encryption.changed.connect(on_smtp_encryption_changed);
        
        check_smtp_noauth.toggled.connect(on_smtp_no_auth_changed);
        
        entry_imap_port.insert_text.connect(on_port_insert_text);
        entry_smtp_port.insert_text.connect(on_port_insert_text);
        
        entry_nickname.insert_text.connect(on_nickname_insert_text);
        
        // Reset the "first update" flag when the window is mapped.
        map.connect(() => { first_ui_update = true; });
    }
    
    // Sets the account information to display on this page.
    public void set_account_information(Geary.AccountInformation info, Geary.Engine.ValidationResult result) {
        set_all_info(info.real_name,
            info.nickname,
            info.email,
            info.imap_credentials.user,
            info.imap_credentials.pass,
            info.imap_remember_password && info.smtp_remember_password,
            info.smtp_credentials != null ? info.smtp_credentials.user : null,
            info.smtp_credentials != null ? info.smtp_credentials.pass : null,
            info.service_provider,
            info.save_sent_mail,
            info.allow_save_sent_mail(),
            info.default_imap_server_host,
            info.default_imap_server_port,
            info.default_imap_server_ssl,
            info.default_imap_server_starttls,
            info.default_smtp_server_host,
            info.default_smtp_server_port,
            info.default_smtp_server_ssl,
            info.default_smtp_server_starttls,
            info.default_smtp_server_noauth,
            info.prefetch_period_days,
            result);
    }
    
    // Can use this instead of set_account_information(), both do the same thing.
    public void set_all_info(
        string? initial_real_name = null,
        string? initial_nickname = null,
        string? initial_email = null,
        string? initial_imap_username = null,
        string? initial_imap_password = null,
        bool initial_remember_password = true,
        string? initial_smtp_username = null,
        string? initial_smtp_password = null,
        int initial_service_provider = Geary.ServiceProvider.GMAIL,
        bool initial_save_sent_mail = true,
        bool allow_save_sent_mail = true,
        string? initial_default_imap_host = null,
        uint16 initial_default_imap_port = Geary.Imap.ClientConnection.DEFAULT_PORT_SSL,
        bool initial_default_imap_ssl = true,
        bool initial_default_imap_starttls = false,
        string? initial_default_smtp_host = null,
        uint16 initial_default_smtp_port = Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL,
        bool initial_default_smtp_ssl = true,
        bool initial_default_smtp_starttls = false,
        bool initial_default_smtp_noauth = false,
        int prefetch_period_days = Geary.AccountInformation.DEFAULT_PREFETCH_PERIOD_DAYS,
        Geary.Engine.ValidationResult result = Geary.Engine.ValidationResult.OK) {
        
        // Set defaults
        real_name = initial_real_name ?? "";
        nickname = initial_nickname ?? "";
        email_address = initial_email ?? "";
        password = initial_imap_password != null ? initial_imap_password : "";
        remember_password = initial_remember_password;
        save_sent_mail = initial_save_sent_mail;
        check_save_sent_mail.sensitive = allow_save_sent_mail;
        set_service_provider((Geary.ServiceProvider) initial_service_provider);
        combo_imap_encryption.active = Encryption.NONE; // Must be default; set to real value below.
        combo_smtp_encryption.active = Encryption.NONE;
        
        // Set defaults for IMAP info
        imap_host = initial_default_imap_host ?? "";
        imap_port = initial_default_imap_port;
        imap_username = initial_imap_username ?? "";
        imap_password = initial_imap_password ?? "";
        imap_ssl = initial_default_imap_ssl;
        imap_starttls = initial_default_imap_starttls;
        
        // Set defaults for SMTP info
        smtp_host = initial_default_smtp_host ?? "";
        smtp_port = initial_default_smtp_port;
        smtp_username = initial_smtp_username ?? "";
        smtp_password = initial_smtp_password ?? "";
        smtp_ssl = initial_default_smtp_ssl;
        smtp_starttls = initial_default_smtp_starttls;
        smtp_noauth = initial_default_smtp_noauth;
        
        set_validation_result(result);
        
        set_storage_length(prefetch_period_days);
    }
    
    public void set_validation_result(Geary.Engine.ValidationResult result) {
        last_validation_result = result;
    }
    
    // Resets all fields to their defaults.
    public void reset_all() {
        // Take advantage of set_all_info()'s defaults.
        set_all_info(get_default_real_name());
        
        edited_imap_port = false;
        edited_smtp_port = false;
    }
    
    /** Puts this page into one of three different modes:
     *  WELCOME: The first screen when Geary is started.
     *      ADD: Add account screen is like the Welcome screen, but without the welcome message.
     *     EDIT: This screen has only a few options that can be modified after creating an account.
     */
    public void set_mode(PageMode m) {
        mode = m;
        update_ui();
    }
    
    public PageMode get_mode() {
        return mode;
    }
    
    // TODO: Only reset if not manually set by user.
    private void on_email_changed() {
        entry_imap_username.text = entry_email.text;
        
        if (entry_smtp_username.sensitive)
            entry_smtp_username.text = entry_email.text;
    }
    
    // TODO: Only reset if not manually set by user.
    private void on_password_changed() {
        entry_imap_password.text = entry_password.text;
        
        if (entry_password.sensitive)
            entry_smtp_password.text = entry_password.text;
    }
    
    private void on_changed() {
        info_changed();
    }
    
    // Prevent non-printable characters in nickname field.
    private void on_nickname_insert_text(Gtk.Editable e, string text, int length, ref int position) {
        unichar c;
        int index = 0;
        while (text.get_next_char(ref index, out c)) {
            if (!c.isprint()) {
                Signal.stop_emission_by_name(e, "insert-text");
                
                return;
            }
        }
    }
    
    private void on_port_insert_text(Gtk.Editable e, string text, int length, ref int position) {
        // Prevent non-numerical characters and ensure port is <= uint16.MAX
        if (!uint64.try_parse(text) || uint64.parse(((Gtk.Entry) e).text) > uint16.MAX) {
            Signal.stop_emission_by_name(e, "insert-text");
        } else {
            if (e == entry_imap_port)
                edited_imap_port = true;
            else if (e == entry_smtp_port)
                edited_smtp_port = true;
        }
    }
    
    private void on_imap_encryption_changed() {
        if (edited_imap_port)
            return;
        
        imap_port = get_default_imap_port();
        edited_imap_port = false;
    }
    
    private uint16 get_default_imap_port() {
        switch (combo_imap_encryption.active) {
            case Encryption.SSL:
                return Geary.Imap.ClientConnection.DEFAULT_PORT_SSL;
            
            case Encryption.NONE:
            case Encryption.STARTTLS:
            default:
                return Geary.Imap.ClientConnection.DEFAULT_PORT;
        }
    }
    
    private void on_smtp_encryption_changed() {
        if (edited_smtp_port)
            return;
        
        smtp_port = get_default_smtp_port();
        edited_smtp_port = false;
    }
    
    private void on_smtp_no_auth_changed() {
        if (check_smtp_noauth.active) {
            smtp_username_store = entry_smtp_username.text;
            smtp_password_store = entry_smtp_password.text;
            
            entry_smtp_username.text = "";
            entry_smtp_password.text = "";
            
            entry_smtp_username.sensitive = false;
            entry_smtp_password.sensitive = false;
        } else {
            entry_smtp_username.text = smtp_username_store;
            entry_smtp_password.text = smtp_password_store;
            
            entry_smtp_username.sensitive = true;
            entry_smtp_password.sensitive = true;
        }
    }
    
    private uint16 get_default_smtp_port() {
        switch (combo_smtp_encryption.active) {
            case Encryption.SSL:
                return Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL;
            
            case Encryption.STARTTLS:
                return Geary.Smtp.ClientConnection.DEFAULT_PORT_STARTTLS;
            
            case Encryption.NONE:
            default:
                return Geary.Smtp.ClientConnection.DEFAULT_PORT;
        }
    }
    
    public bool is_complete() {
        switch (get_service_provider()) {
            case Geary.ServiceProvider.OTHER:
                if (Geary.String.is_empty_or_whitespace(nickname) ||
                    Geary.String.is_empty_or_whitespace(email_address) ||
                    Geary.String.is_empty_or_whitespace(imap_host) ||
                    Geary.String.is_empty_or_whitespace(imap_port.to_string()) ||
                    Geary.String.is_empty_or_whitespace(imap_username) ||
                    Geary.String.is_empty_or_whitespace(imap_password) ||
                    Geary.String.is_empty_or_whitespace(smtp_host) ||
                    Geary.String.is_empty_or_whitespace(smtp_port.to_string()) ||
                    Geary.String.is_empty_or_whitespace(smtp_username) && check_smtp_noauth.active == false ||
                    Geary.String.is_empty_or_whitespace(smtp_password) && check_smtp_noauth.active == false)
                    return false;
            break;
            
            // GMAIL, YAHOO, and OUTLOOK
            default:
                if (Geary.String.is_empty_or_whitespace(nickname) ||
                    Geary.String.is_empty_or_whitespace(email_address) ||
                    Geary.String.is_empty_or_whitespace(password))
                    return false;
            break;
        }
        
        return true;
    }
    
    public Geary.AccountInformation? get_account_information() {
        Geary.AccountInformation account_information;
        fix_credentials_for_supported_provider();
        
        Geary.Credentials imap_credentials = new Geary.Credentials(imap_username.strip(), imap_password.strip());
        Geary.Credentials smtp_credentials = new Geary.Credentials(smtp_username.strip(), smtp_password.strip());
        
        try {
            Geary.AccountInformation original_account = Geary.Engine.instance.get_accounts().get(email_address);
            if (original_account == null) {
                // New account.
                account_information = Geary.Engine.instance.create_orphan_account(email_address);
            } else {
                // Existing account: create a copy so we don't mess up the original.
                account_information = new Geary.AccountInformation.temp_copy(original_account);
            }
        } catch (Error err) {
            debug("Unable to open account information for %s: %s", email_address, err.message);
            
            return null;
        }
        
        account_information.real_name = real_name.strip();
        account_information.nickname = nickname.strip();
        account_information.imap_credentials = imap_credentials;
        account_information.smtp_credentials = smtp_credentials;
        account_information.imap_remember_password = remember_password;
        account_information.smtp_remember_password = remember_password;
        account_information.service_provider = get_service_provider();
        account_information.save_sent_mail = save_sent_mail;
        account_information.default_imap_server_host = imap_host;
        account_information.default_imap_server_port = imap_port;
        account_information.default_imap_server_ssl = imap_ssl;
        account_information.default_imap_server_starttls = imap_starttls;
        account_information.default_smtp_server_host = smtp_host.strip();
        account_information.default_smtp_server_port = smtp_port;
        account_information.default_smtp_server_ssl = smtp_ssl;
        account_information.default_smtp_server_starttls = smtp_starttls;
        account_information.default_smtp_server_noauth = smtp_noauth;
        account_information.prefetch_period_days = get_storage_length();
        
        if (smtp_noauth)
            account_information.smtp_credentials = null;
        
        on_changed();
        
        return account_information;
    }
    
    // Assembles credentials for supported providers.
    private void fix_credentials_for_supported_provider() {
        if (get_service_provider() != Geary.ServiceProvider.OTHER) {
            imap_username = email_address;
            smtp_username = email_address;
            imap_password = password;
            smtp_password = password;
        }
    }
    
    // Updates UI based on various options.
    internal void update_ui() {
        base.show_all();
        welcome_box.visible = mode == PageMode.WELCOME;
        entry_nickname.visible = label_nickname.visible = mode != PageMode.WELCOME;
        storage_container.visible = mode == PageMode.EDIT;
        check_save_sent_mail.visible = mode != PageMode.WELCOME;
        
        if (get_service_provider() == Geary.ServiceProvider.OTHER) {
            // Display all options for custom providers.
            label_password.hide();
            entry_password.hide();
            other_info.show();
            set_other_info_sensitive(true);
            check_remember_password.label = _("Remem_ber passwords"); // Plural
        } else {
            // For special-cased providers, only display necessary info.
            label_password.show();
            entry_password.show();
            other_info.hide();
            set_other_info_sensitive(mode == PageMode.WELCOME);
            check_remember_password.label = _("Remem_ber password");
        }
        
        // In edit mode, certain fields are not sensitive.
        combo_service.sensitive =
            entry_email.sensitive =
            entry_imap_host.sensitive =
            entry_imap_port.sensitive =
            entry_imap_username.sensitive =
            combo_imap_encryption.sensitive =
            entry_smtp_host.sensitive =
            entry_smtp_port.sensitive =
            entry_smtp_username.sensitive =
            combo_smtp_encryption.sensitive =
            check_smtp_noauth.sensitive =
                mode != PageMode.EDIT;
        
        if (smtp_noauth) {
            entry_smtp_username.sensitive = false;
            entry_smtp_password.sensitive = false;
        }
        
        // Update error text.
        label_error.visible = false;
        if (last_validation_result == Geary.Engine.ValidationResult.OK) {
            label_error.visible = false;
        } else {
            label_error.visible = true;
            
            string error_string = _("Unable to validate:\n");
            if (last_validation_result.is_all_set(Geary.Engine.ValidationResult.INVALID_NICKNAME))
                error_string += _("        &#8226; Invalid account nickname.\n");
            
            if (last_validation_result.is_all_set(Geary.Engine.ValidationResult.EMAIL_EXISTS))
                error_string += _("        &#8226; Email address already added to Geary.\n");
            
            if (get_service_provider() == Geary.ServiceProvider.OTHER) {
                if (last_validation_result.is_all_set(Geary.Engine.ValidationResult.IMAP_CONNECTION_FAILED))
                    error_string += _("        &#8226; IMAP connection error.\n");
                
                if (last_validation_result.is_all_set(Geary.Engine.ValidationResult.IMAP_CREDENTIALS_INVALID))
                    error_string += _("        &#8226; IMAP username or password incorrect.\n");
                
                if (last_validation_result.is_all_set(Geary.Engine.ValidationResult.SMTP_CONNECTION_FAILED))
                    error_string += _("        &#8226; SMTP connection error.\n");
                
                if (last_validation_result.is_all_set(Geary.Engine.ValidationResult.SMTP_CREDENTIALS_INVALID))
                    error_string += _("        &#8226; SMTP username or password incorrect.\n");
            } else {
                if (last_validation_result.is_all_set(Geary.Engine.ValidationResult.IMAP_CONNECTION_FAILED) ||
                    last_validation_result.is_all_set(Geary.Engine.ValidationResult.SMTP_CONNECTION_FAILED))
                    error_string += _("        &#8226; Connection error.\n");
                
                if (last_validation_result.is_all_set(Geary.Engine.ValidationResult.IMAP_CREDENTIALS_INVALID) ||
                    last_validation_result.is_all_set(Geary.Engine.ValidationResult.SMTP_CREDENTIALS_INVALID))
                    error_string += _("        &#8226; Username or password incorrect.\n");
            }
            
            label_error.label = "<span color=\"red\">" + error_string + "</span>";
        }
        
        size_changed();
        
        // Set initial field focus.
        // This has to be done here because the window isn't completely setup until the first time
        // this method runs.
        if (first_ui_update && parent.get_visible()) {
            if (mode == PageMode.EDIT) {
                if (get_service_provider() != Geary.ServiceProvider.OTHER)
                    entry_password.grab_focus();
                else
                    entry_imap_password.grab_focus();
            } else {
                if (Geary.String.is_empty(real_name))
                    entry_real_name.grab_focus();
                else if (mode == PageMode.ADD)
                    entry_nickname.grab_focus();
                else
                    entry_email.grab_focus();
            }
            
            first_ui_update = false;
        }
    }
    
    public Geary.ServiceProvider get_service_provider() {
        return (Geary.ServiceProvider) combo_service.get_active();
    }
    
    public void set_service_provider(Geary.ServiceProvider provider) {
        foreach (Geary.ServiceProvider p in Geary.ServiceProvider.get_providers()) {
            if (p == provider)
                combo_service.set_active(p);
        }
        
        if (combo_service.get_active() == -1)
            combo_service.set_active(0);
    }
    
    // Greys out "other info" (server settings, etc.)
    public void set_other_info_sensitive(bool sensitive) {
        entry_imap_host.sensitive = sensitive;
        entry_imap_port.sensitive = sensitive;
        entry_imap_username.sensitive = sensitive;
        entry_imap_password.sensitive = sensitive;
        combo_imap_encryption.sensitive = sensitive;
        
        entry_smtp_host.sensitive = sensitive;
        entry_smtp_port.sensitive = sensitive;
        entry_smtp_username.sensitive = sensitive;
        entry_smtp_password.sensitive = sensitive;
        combo_smtp_encryption.sensitive = sensitive;
    }
    
    // Since users of this class embed it in a Gtk.Notebook, we're forced to override this method
    // to prevent hidden UI elements from appearing.
    public override void show_all() {
        // Note that update_ui() calls base.show_all(), so no need to do that here.
        update_ui();
    }
    
    private string get_default_real_name() {
        string real_name = Environment.get_real_name();
        return real_name == "Unknown" ? "" : real_name;
    }
    
    // Sets the storage length combo box.  The days parameter should correspond to one of the pre-set
    // values; arbitrary numbers will put the combo box into an undetermined state.
    private void set_storage_length(int days) {
        combo_storage_length.set_active_id(days.to_string());
    }
    
    // Returns number of days.
    private int get_storage_length() {
        return int.parse(combo_storage_length.get_active_id());
    }
    
    private bool combo_storage_separator_delegate(Gtk.TreeModel model, Gtk.TreeIter iter) {
        GLib.Value v;
        model.get_value(iter, 0, out v);
        
        return v.get_string() == ".";
    }
}

