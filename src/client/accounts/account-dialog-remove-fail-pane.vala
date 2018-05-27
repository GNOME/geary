/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Lets user know that account removal cannot be completed..
public class AccountDialogRemoveFailPane : AccountDialogPane {
    public signal void ok();

    public AccountDialogRemoveFailPane(Gtk.Stack stack) {
        base(stack);

        Gtk.Builder builder = GioUtil.create_builder("account_cannot_remove.glade");
        pack_end((Gtk.Box) builder.get_object("container"));
        Gtk.ActionGroup actions = (Gtk.ActionGroup) builder.get_object("actions");
        actions.get_action("ok_action").activate.connect(() => { ok(); });
    }
}
