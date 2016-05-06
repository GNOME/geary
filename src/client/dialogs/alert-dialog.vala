/* Copyright 2016 Software Freedom Conservancy Inc.
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
        
        dialog.text = primary;
        dialog.secondary_text = secondary;
        
        if (!Geary.String.is_empty_or_whitespace(tertiary_button))
            dialog.add_button(tertiary_button, tertiary_response_type);
        
        if (!Geary.String.is_empty_or_whitespace(cancel_button))
            dialog.add_button(cancel_button, Gtk.ResponseType.CANCEL);
        
        if (!Geary.String.is_empty_or_whitespace(ok_button))
            dialog.add_button(ok_button, Gtk.ResponseType.OK);
    }
    
    public void use_secondary_markup(bool markup) {
        dialog.secondary_use_markup = markup;
    }
    
    public Gtk.Box get_message_area() {
        return (Gtk.Box) dialog.get_message_area();
    }

    public void set_focus_response(Gtk.ResponseType response) {
        Gtk.Widget? to_focus = dialog.get_widget_for_response(response);
        if (to_focus != null)
            to_focus.grab_focus();
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
        base (parent, Gtk.MessageType.WARNING, primary, secondary, ok_button, Stock._CANCEL,
            null, Gtk.ResponseType.NONE);
    }
}

class TernaryConfirmationDialog : AlertDialog {
    public TernaryConfirmationDialog(Gtk.Window? parent, string primary, string? secondary,
        string? ok_button, string? tertiary_button, Gtk.ResponseType tertiary_response_type) {
        base (parent, Gtk.MessageType.WARNING, primary, secondary, ok_button,  Stock._CANCEL,
            tertiary_button, tertiary_response_type);
    }
}

class ErrorDialog : AlertDialog {
    public ErrorDialog(Gtk.Window? parent, string primary, string? secondary) {
        base (parent, Gtk.MessageType.ERROR, primary, secondary, Stock._OK, null, null,
            Gtk.ResponseType.NONE);
    }
}

class QuestionDialog : AlertDialog {
    public bool is_checked { get; private set; default = false; }
    
    private Gtk.CheckButton? checkbutton = null;
    
    public QuestionDialog(Gtk.Window? parent, string primary, string? secondary, string yes_button,
        string no_button) {
        base (parent, Gtk.MessageType.QUESTION, primary, secondary, yes_button, no_button, null,
            Gtk.ResponseType.NONE);
    }
    
    public QuestionDialog.with_checkbox(Gtk.Window? parent, string primary, string? secondary,
        string yes_button, string no_button, string checkbox_label, bool checkbox_default) {
        this (parent, primary, secondary, yes_button, no_button);
        
        checkbutton = new Gtk.CheckButton.with_mnemonic(checkbox_label);
        checkbutton.active = checkbox_default;
        checkbutton.halign = Gtk.Align.END;
        checkbutton.toggled.connect(on_checkbox_toggled);
        
        get_message_area().pack_start(checkbutton);
        
        // this must be done once all the packing is completed
        get_message_area().show_all();

        // the check box may have grabbed keyboard focus, so we put it back to the button
        set_focus_response(Gtk.ResponseType.OK);
        
        is_checked = checkbox_default;
    }
    
    private void on_checkbox_toggled() {
        is_checked = checkbutton.active;
    }
}

