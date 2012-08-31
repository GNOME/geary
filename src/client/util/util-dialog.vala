/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class AlertDialog : Object {
    private Gtk.MessageDialog dialog;
    
    public AlertDialog(Gtk.Window? parent, Gtk.MessageType message_type, string primary, string? secondary,
        string? ok_button, string? cancel_button, string? tertiary_button,
        Gtk.ResponseType tertiary_response_type) {
        dialog = new Gtk.MessageDialog(parent, Gtk.DialogFlags.DESTROY_WITH_PARENT, message_type,
            Gtk.ButtonsType.NONE, "");
        
        if (secondary != null)
            dialog.set_markup("<span weight=\"bold\" size=\"larger\">%s</span>\n\n%s".printf(primary, secondary));
        else
            dialog.set_markup("<span weight=\"bold\" size=\"larger\">%s</span>".printf(primary));
        
        if (!Geary.String.is_empty_or_whitespace(tertiary_button))
            dialog.add_button(tertiary_button, tertiary_response_type);
        
        if (!Geary.String.is_empty_or_whitespace(cancel_button))
            dialog.add_button(cancel_button, Gtk.ResponseType.CANCEL);
        
        if (!Geary.String.is_empty_or_whitespace(ok_button))
            dialog.add_button(ok_button, Gtk.ResponseType.OK);
    }
    
    // Runs dialog, destroys it, and returns selected response
    public Gtk.ResponseType run() {
        Gtk.ResponseType response = (Gtk.ResponseType) dialog.run();
        
        dialog.destroy();
        
        return response;
    }
}

class ConfirmationDialog : AlertDialog {
    public ConfirmationDialog(Gtk.Window? parent, string primary, string? secondary, string? ok_button) {
        base (parent, Gtk.MessageType.WARNING, primary, secondary, ok_button, Gtk.Stock.CANCEL,
            null, Gtk.ResponseType.NONE);
    }
}

class ErrorDialog : AlertDialog {
    public ErrorDialog(Gtk.Window? parent, string primary, string? secondary) {
        base (parent, Gtk.MessageType.ERROR, primary, secondary, Gtk.Stock.OK, null, null,
            Gtk.ResponseType.NONE);
    }
}

