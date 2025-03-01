/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Displays a dialog for collecting the user's password, without allowing them to change their
 * other data.
 */
[GtkTemplate (ui = "/org/gnome/Geary/password-dialog.ui")]
public class PasswordDialog : Adw.AlertDialog {

    [GtkChild] private unowned Adw.PreferencesGroup prefs_group;
    [GtkChild] private unowned Adw.ActionRow username_row;
    [GtkChild] private unowned Adw.PasswordEntryRow password_row;
    [GtkChild] private unowned Adw.SwitchRow remember_password_row;

    public PasswordDialog(Gtk.Window? parent,
                          Geary.AccountInformation account,
                          Geary.ServiceInformation service,
                          Geary.Credentials? credentials) {
        if (credentials != null) {
            this.username_row.subtitle = credentials.user;
            this.password_row.text = credentials.token ?? "";
        }
        this.remember_password_row.active = service.remember_password;

        if ((service.protocol == Geary.Protocol.SMTP)) {
            this.prefs_group.title = _("SMTP Credentials");
        }

        refresh_ok_button_sensitivity();
        this.password_row.changed.connect(refresh_ok_button_sensitivity);
    }

    private void refresh_ok_button_sensitivity() {
        string password = this.password_row.text;
        set_response_enabled("authenticate", !Geary.String.is_empty_or_whitespace(password));
    }

    public async string? get_password(Gtk.Window? parent,
                                      out bool remember_password) {
        string response = yield choose(parent, null);

        if (response == "cancel") {
            remember_password = false;
            return null;
        }

        remember_password = this.remember_password_row.active;
        string password = this.password_row.text;
        close();
        return password;
    }
}

