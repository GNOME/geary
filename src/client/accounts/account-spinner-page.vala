/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Shows a simple spinner and a message indicating the account is being validated.
public class AccountSpinnerPage : Gtk.Box {
    public AccountSpinnerPage() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 4);

        Gtk.Builder builder = GioUtil.create_builder("account_spinner.glade");
        pack_end((Gtk.Box) builder.get_object("container"));
    }
}
