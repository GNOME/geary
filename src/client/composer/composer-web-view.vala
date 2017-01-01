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


    private const string HTML_BODY = """
        <html><head><title></title>
        <style>
        body {
            margin: 0px !important;
            padding: 0 !important;
            background-color: white !important;
            font-size: medium !important;
        }
        body.plain, body.plain * {
            font-family: monospace !important;
            font-weight: normal;
            font-style: normal;
            font-size: medium !important;
            color: black;
            text-decoration: none;
        }
        body.plain a {
            cursor: text;
        }
        #message-body {
            box-sizing: border-box;
            padding: 10px;
            outline: 0px solid transparent;
            min-height: 100%;
        }
        blockquote {
            margin-top: 0px;
            margin-bottom: 0px;
            margin-left: 10px;
            margin-right: 10px;
            padding-left: 5px;
            padding-right: 5px;
            background-color: white;
            border: 0;
            border-left: 3px #aaa solid;
        }
        pre {
            white-space: pre-wrap;
            margin: 0;
        }
        </style>
        </head><body>
        <div id="message-body" contenteditable="true" dir="auto">%s</div>
        </body></html>""";
    private const string CURSOR = "<span id=\"cursormarker\"></span>";

    private static WebKit.UserScript? app_script = null;

    public static void load_resources()
        throws Error {
        ComposerWebView.app_script = ClientWebView.load_app_script(
            "composer-web-view.js"
        );
    }

    private bool is_shift_down = false;


    public ComposerWebView(Configuration config) {
        base(config);
        this.user_content_manager.add_script(ComposerWebView.app_script);
        // this.should_insert_text.connect(on_should_insert_text);
        this.key_press_event.connect(on_key_press_event);
    }

    /**
     * Loads a message HTML body into the view.
     */
    public new void load_html(string? body, string? signature, bool top_posting) {
        string html = "";
        signature = signature ?? "";

        if (body == null)
            html = CURSOR + "<br /><br />" + signature;
        else if (top_posting)
            html = CURSOR + "<br /><br />" + signature + body;
        else
            html = body + CURSOR + "<br /><br />" + signature;

        base.load_html(HTML_BODY.printf(html));
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
    public void set_rich_text(bool enabled) {
        this.run_javascript.begin(
            "geary.setRichText(%s);".printf(enabled ? "true" : "false"), null
        );
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
        this.run_javascript.begin("geary.undoBlockquoteStyle();", null);
    }

    /**
     * Returns the editor content as an HTML string.
     */
    public async string? get_html() throws Error {
        WebKit.JavascriptResult result = yield this.run_javascript(
            "geary.getHtml();", null
        );
        return WebKitUtil.to_string(result);
    }

    /**
     * Returns the editor text as RFC 3676 format=flowed text.
     */
    public async string? get_text() throws Error {
        WebKit.JavascriptResult result = yield this.run_javascript(
            "geary.getText();", null
        );

        const int MAX_BREAKABLE_LEN = 72; // F=F recommended line limit
        const int MAX_UNBREAKABLE_LEN = 998; // SMTP line limit

        string body_text = WebKitUtil.to_string(result);
        string[] lines = body_text.split("\n");
        GLib.StringBuilder flowed = new GLib.StringBuilder.sized(body_text.length);
        foreach (string line in lines) {
            // Strip trailing whitespace, so it doesn't look like a
            // flowed line.  But the signature separator "-- " is
            // special, so leave that alone.
            if (line != "-- ")
                line = line.chomp();

            // Determine quoting depth by counting the the number of
            // QUOTE_MARKERs present, and build a quote prefix for it.
            int quote_level = 0;
            while (line[quote_level] == Geary.RFC822.Utils.QUOTE_MARKER)
                quote_level += 1;
            line = line[quote_level:line.length];
            string prefix = quote_level > 0 ? string.nfill(quote_level, '>') + " " : "";

            // Check to see if the line (with quote prefix) is longer
            // than the recommended limit, if so work out where to do
            int max_breakable = MAX_BREAKABLE_LEN - prefix.length;
            int max_unbreakable = MAX_UNBREAKABLE_LEN - prefix.length;
            do {
                int start_ind = 0;

                // Space stuff if needed
                if (quote_level == 0 &&
                    (line.has_prefix(">") || line.has_prefix("From"))) {
                    line = " " + line;
                    start_ind = 1;
                }

                // Check to see if we need to break the line, if so
                // determine where to do it.
                int cut_ind = line.length;
                if (cut_ind > max_breakable) {
                    // Line needs to be broken, look for the last
                    // useful place to break before before the
                    // max recommended length.
                    string beg = line[0:max_breakable];
                    cut_ind = beg.last_index_of(" ", start_ind) + 1;
                    if (cut_ind == 0) {
                        // No natural places to break found, so look
                        // for place further along, and if that is
                        // also not found then break on the SMTP max
                        // line length.
                        cut_ind = line.index_of(" ", start_ind) + 1;
                        if (cut_ind == 0)
                            cut_ind = line.length;
                        if (cut_ind > max_unbreakable)
                            cut_ind = max_unbreakable;
                    }
                }

                // Actually break the line
                flowed.append(prefix + line[0:cut_ind] + "\n");
                line = line[cut_ind:line.length];
            } while (line.length > 0);
        }

        return flowed.str;
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
