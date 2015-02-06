/* Copyright 2013-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Lets user know that account removal cannot be completed..
public class AccountDialogSpinnerPane : AccountDialogPane {
    public AccountDialogSpinnerPane(Gtk.Stack stack) {
        base(stack);
        
        pack_end(new AccountSpinnerPage());
    }
}

