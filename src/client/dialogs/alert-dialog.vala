/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

class AlertDialog : Object {
    private Gtk.MessageDialog dialog;

    public AlertDialog(Gtk.Window? parent, Gtk.MessageType message_type, string title,
        string? description, string? ok_button, string? cancel_button, string? tertiary_button,
        Gtk.ResponseType tertiary_response_type, string? ok_action_type,
        string? tertiary_action_type = "", Gtk.ResponseType? default_response = null) {

        dialog = new Gtk.MessageDialog(parent, Gtk.DialogFlags.DESTROY_WITH_PARENT, message_type,
            Gtk.ButtonsType.NONE, "");

        dialog.text = title;
        dialog.secondary_text = description;

        if (!Geary.String.is_empty_or_whitespace(tertiary_button)) {
            Gtk.Widget? button = dialog.add_button(tertiary_button, tertiary_response_type);
            if (!Geary.String.is_empty_or_whitespace(tertiary_action_type)) {
                button.get_style_context().add_class(tertiary_action_type);
            }
        }

        if (!Geary.String.is_empty_or_whitespace(cancel_button))
            dialog.add_button(cancel_button, Gtk.ResponseType.CANCEL);

        if (!Geary.String.is_empty_or_whitespace(ok_button)) {
            Gtk.Widget? button = dialog.add_button(ok_button, Gtk.ResponseType.OK);
            if (!Geary.String.is_empty_or_whitespace(ok_action_type)) {
                button.get_style_context().add_class(ok_action_type);
            }
        }

        if (default_response != null) {
            dialog.set_default_response(default_response);
        }
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
    public ConfirmationDialog(Gtk.Window? parent, string title, string? description,
        string? ok_button, string? ok_action_type = "") {
        base (parent, Gtk.MessageType.WARNING, title, description, ok_button, Stock._CANCEL,
            null, Gtk.ResponseType.NONE, ok_action_type);
    }
}

class TernaryConfirmationDialog : AlertDialog {
    public TernaryConfirmationDialog(Gtk.Window? parent, string title, string? description,
        string? ok_button, string? tertiary_button, Gtk.ResponseType tertiary_response_type,
        string? ok_action_type = "", string? tertiary_action_type = "",
        Gtk.ResponseType? default_response = null) {

        base (parent, Gtk.MessageType.WARNING, title, description, ok_button, Stock._CANCEL,
            tertiary_button, tertiary_response_type, ok_action_type, tertiary_action_type,
            default_response);
    }
}

class ErrorDialog : AlertDialog {
    public ErrorDialog(Gtk.Window? parent, string title, string? description) {
        base (parent, Gtk.MessageType.ERROR, title, description, Stock._OK, null, null,
            Gtk.ResponseType.NONE, null);
    }
}

class QuestionDialog : AlertDialog {
    public bool is_checked { get; private set; default = false; }

    private Gtk.CheckButton? checkbutton = null;

    public QuestionDialog(Gtk.Window? parent, string title, string? description,
        string yes_button, string no_button) {
        base (parent, Gtk.MessageType.QUESTION, title, description, yes_button, no_button, null,
            Gtk.ResponseType.NONE, "suggested-action");
    }

    public QuestionDialog.with_checkbox(Gtk.Window? parent, string title, string? description,
        string yes_button, string no_button, string checkbox_label, bool checkbox_default) {
        this (parent, title, description, yes_button, no_button);

        checkbutton = new Gtk.CheckButton.with_mnemonic(checkbox_label);
        checkbutton.active = checkbox_default;
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

