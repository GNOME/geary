/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Displays a dialog for collecting the user's password, without allowing them to change their
 * other data.
 */
public class PasswordDialog {
    // We can't keep these in the glade file, because Gnome doesn't want markup in translatable
    // strings, and Glade doesn't support the "larger" size attribute. See this bug report for
    // details: https://bugzilla.gnome.org/show_bug.cgi?id=679006
    private const string PRIMARY_TEXT_MARKUP = "<span weight=\"bold\" size=\"larger\">%s</span>";
    private const string PRIMARY_TEXT_FIRST_TRY = _("Geary requires your email password to continue");

    private Gtk.Dialog dialog;
    private Gtk.Entry entry_password;
    private Gtk.CheckButton check_remember_password;
    private Gtk.Button ok_button;

    public string password { get; private set; default = ""; }
    public bool remember_password { get; private set; }

    public PasswordDialog(Gtk.Window? parent,
                          Geary.AccountInformation account,
                          Geary.ServiceInformation service,
                          Geary.Credentials? credentials) {
        Gtk.Builder builder = GioUtil.create_builder("password-dialog.glade");

        dialog = (Gtk.Dialog) builder.get_object("PasswordDialog");
        dialog.transient_for = parent;
        dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG);
        dialog.set_default_response(Gtk.ResponseType.OK);

        entry_password = (Gtk.Entry) builder.get_object("entry: password");
        check_remember_password = (Gtk.CheckButton) builder.get_object("check: remember_password");

        Gtk.Label label_username = (Gtk.Label) builder.get_object("label: username");
        Gtk.Label label_smtp = (Gtk.Label) builder.get_object("label: smtp");

        // Load translated text for labels with markup unsupported by glade.
        Gtk.Label primary_text_label = (Gtk.Label) builder.get_object("primary_text_label");
        primary_text_label.set_markup(PRIMARY_TEXT_MARKUP.printf(PRIMARY_TEXT_FIRST_TRY));

        if (credentials != null) {
            label_username.set_text(credentials.user);
            entry_password.set_text(credentials.token ?? "");
        }
        check_remember_password.active = service.remember_password;

        if ((service.protocol == Geary.Protocol.SMTP)) {
            label_smtp.show();
        }

        ok_button = (Gtk.Button) builder.get_object("authenticate_button");

        refresh_ok_button_sensitivity();
        entry_password.changed.connect(refresh_ok_button_sensitivity);
    }

    private void refresh_ok_button_sensitivity() {
        ok_button.sensitive = !Geary.String.is_empty_or_whitespace(entry_password.get_text());
    }

    public bool run() {
        dialog.show();

        Gtk.ResponseType response = (Gtk.ResponseType) dialog.run();
        if (response == Gtk.ResponseType.OK) {
            password = entry_password.get_text();
            remember_password = check_remember_password.active;
        }

        dialog.destroy();

        return (response == Gtk.ResponseType.OK);
    }
}

