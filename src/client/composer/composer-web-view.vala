/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A WebView for editing messages in the composer.
 */
public class ComposerWebView : ClientWebView {


    private bool is_shift_down = false;


    public signal void text_attributes_changed(uint wk_typing_attrs);


    public ComposerWebView() {
        get_editor_state().notify["typing-attributes"].connect(() => {
                text_attributes_changed(get_editor_state().typing_attributes);
            });

        // this.should_insert_text.connect(on_should_insert_text);
        this.key_press_event.connect(on_key_press_event);
    }

    public bool can_undo() {
        // can_execute_editing_command.begin(
        //     WebKit.EDITING_COMMAND_UNDO,
        //     null,
        //     (obj, res) => {
        //         return can_execute_editing_command.end(res);
        //     });
        return false;
    }

    public bool can_redo() {
        // can_execute_editing_command.begin(
        //     WebKit.EDITING_COMMAND_REDO,
        //     null,
        //     (obj, res) => {
        //         return can_execute_editing_command.end(res);
        //     });
        return false;
    }

    /**
     * Sends a cut command to the editor.
     */
    public void cut_clipboard() {
        execute_editing_command(WebKit.EDITING_COMMAND_CUT);
    }

    public bool can_cut_clipboard() {
        // can_execute_editing_command.begin(
        //     WebKit.EDITING_COMMAND_CUT,
        //     null,
        //     (obj, res) => {
        //         return can_execute_editing_command.end(res);
        //     });
        return false;
    }

    /**
     * Sends a paste command to the editor.
     */
    public void paste_clipboard() {
        execute_editing_command(WebKit.EDITING_COMMAND_PASTE);
    }

    public bool can_paste_clipboard() {
        // can_execute_editing_command.begin(
        //     WebKit.EDITING_COMMAND_PASTE,
        //     null,
        //     (obj, res) => {
        //         return can_execute_editing_command.end(res);
        //     });
        return false;
    }

    /**
     * Inserts some text at the current cursor location.
     */
    public void insert_text(string text) {
        // XXX
    }

    /**
     * Inserts some text at the current cursor location, quoting it.
     */
    public void insert_quote(string text) {
        // XXX
    }

    /**
     * Sets whether the editor is in rich text or plain text mode.
     */
    public void enable_rich_text(bool enabled) {
        // XXX
    }

    /**
     * ???
     */
    public void linkify_document() {
        // XXX
    }

    /**
     * ???
     */
    public string get_block_quote_representation() {
        return ""; // XXX
    }

    /**
     * ???
     */
    public void undo_blockquote_style() {
        // XXX
    }

    /**
     * Returns the editor content as an HTML string.
     */
    public string get_html() {
        return ""; // XXX
    }

    /**
     * Returns the editor content as a plain text string.
     */
    public string get_text() {
        return ""; // XXX
    }

    /**
     * ???
     */
    public void load_finished_and_realised() {
        // XXX
    }

    /**
     * ???
     */
    public bool handle_key_press(Gdk.EventKey event) {
        // XXX
        return false;
    }

    // We really want to examine
    // Gdk.Keymap.get_default().get_modifier_state(), instead of
    // storing whether the shift key is down at each keypress, but it
    // isn't yet available in the Vala bindings.
    private bool on_key_press_event (Gdk.EventKey event) {
        is_shift_down = (event.state & Gdk.ModifierType.SHIFT_MASK) != 0;
        return false;
    }

}
