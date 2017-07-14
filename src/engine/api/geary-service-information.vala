/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public abstract class Geary.ServiceInformation : GLib.Object {
    public const string METHOD_LIBSECRET = "libsecret";
    public const string METHOD_GOA = "goa";

    public string host { get; set; default = ""; }
    public uint16 port { get; set; }
    public bool use_starttls { get; set; default = false; }
    public bool use_ssl { get; set; default = true; }
    public bool remember_password { get; set; default = false; }
    public Geary.Credentials credentials { get; set; default = new Geary.Credentials(null, null); }
    public Geary.Service service { get; set; }
    public Geary.CredentialsMediator? mediator { get; set; default = null; }
    public string credentials_method { get; set; default = ""; }

    // Used with SMTP servers
    public bool smtp_noauth { get; set; default = false; }
    public bool smtp_use_imap_credentials { get; set; default = false; }

    public abstract void load_settings(KeyFile? key_file = null) throws Error;

    public abstract void load_credentials(KeyFile? key_file = null, string? email_address = null) throws Error;

    public abstract void save_settings(KeyFile? key_file = null);

    public void copy_from(Geary.ServiceInformation from) {
        this.host = from.host;
        this.port = from.port;
        this.use_starttls = from.use_starttls;
        this.use_ssl = from.use_ssl;
        this.remember_password = from.remember_password;
        this.credentials = from.credentials;
        this.service = from.service;
        this.mediator = from.mediator;
        this.credentials_method = from.credentials_method;
        this.smtp_noauth = from.smtp_noauth;
        this.smtp_use_imap_credentials = from.smtp_use_imap_credentials;
    }

    public void set_password(string password, bool remember = false) {
        this.credentials = new Credentials(this.credentials.user, password);
        this.remember_password = remember;
    }
}
