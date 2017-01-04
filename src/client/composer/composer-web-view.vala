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


    private const string COMMAND_STACK_CHANGED = "commandStackChanged";
    private const string CURSOR_STYLE_CHANGED = "cursorStyleChanged";

    private const string[] SANS_FAMILY_NAMES = {
        "sans", "arial", "trebuchet", "helvetica"
    };
    private const string[] SERIF_FAMILY_NAMES = {
        "serif", "georgia", "times"
    };
    private const string[] MONO_FAMILY_NAMES = {
        "monospace", "courier", "console"
    };

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
        <div id="message-body" dir="auto">%s</div>
        </body></html>""";
    private const string CURSOR = "<span id=\"cursormarker\"></span>";

    private static Gee.HashMap<string,string> font_family_map =
        new Gee.HashMap<string,string>();

    static construct {
        foreach (string name in SANS_FAMILY_NAMES) {
            font_family_map["sans"] = name;
        }
        foreach (string name in SERIF_FAMILY_NAMES) {
            font_family_map["serif"] = name;
        }
        foreach (string name in MONO_FAMILY_NAMES) {
            font_family_map["monospace"] = name;
        }
    }

    private static WebKit.UserScript? app_script = null;

    public static void load_resources()
        throws Error {
        ComposerWebView.app_script = ClientWebView.load_app_script(
            "composer-web-view.js"
        );
    }

    /** Determines if the view contains any edited text */
    public bool is_empty { get; private set; default = false; }

    /** Determines if the view is in rich text mode */
    public bool is_rich_text { get; private set; default = true; }

    private bool is_shift_down = false;


    /** Emitted when the web view's undo/redo stack has changed. */
    public signal void command_stack_changed(bool can_undo, bool can_redo);

    /** Emitted when the style under the cursor has changed. */
    public signal void cursor_style_changed(string face, uint size);


    public ComposerWebView(Configuration config) {
        base(config);
        this.user_content_manager.add_script(ComposerWebView.app_script);
        // this.should_insert_text.connect(on_should_insert_text);
        this.key_press_event.connect(on_key_press_event);

        this.user_content_manager.script_message_received[COMMAND_STACK_CHANGED].connect(
            (result) => {
                try {
                    string[] values = WebKitUtil.to_string(result).split(",");
                    command_stack_changed(values[0] == "true", values[1] == "true");
                } catch (Geary.JS.Error err) {
                    debug("Could not get command stack state: %s", err.message);
                } finally {
                    result.unref();
                }
            });
                    result.unref();
        this.user_content_manager.script_message_received[CURSOR_STYLE_CHANGED].connect(
            on_cursor_style_changed_message
        );

        register_message_handler(COMMAND_STACK_CHANGED);
        register_message_handler(CURSOR_STYLE_CHANGED);
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


    /**
     * Undoes the last edit operation.
     */
    public void undo() {
        this.run_javascript.begin("geary.undo();", null);
    }

    /**
     * Redoes the last undone edit operation.
     */
    public void redo() {
        this.run_javascript.begin("geary.redo();", null);
    }

    /**
     * Cuts selected content and sends it to the clipboard.
     */
    public void cut_clipboard() {
        execute_editing_command(WebKit.EDITING_COMMAND_CUT);
    }

    /**
     * Pastes plain text from the clipboard into the view.
     */
    public void paste_plain_text() {
        get_clipboard(Gdk.SELECTION_CLIPBOARD).request_text((clipboard, text) => {
                if (text != null) {
                    insert_text(text);
                }
            });
    }

    /**
     * Pastes rich text from the clipboard into the view.
     */
    public void paste_rich_text() {
        execute_editing_command(WebKit.EDITING_COMMAND_PASTE);
    }

    /**
     * Inserts some text at the current cursor location.
     */
    public void insert_text(string text) {
        execute_editing_command_with_argument("inserttext", text);

        // XXX scroll to insertion point:

        // The inserttext command will not scroll if needed, but we
        // can't use the clipboard for plain text. WebKit allows us to
        // scroll a node into view, but not an arbitrary position
        // within a text node. So we add a placeholder node at the
        // cursor position, scroll to that, then remove the
        // placeholder node.
        // try {
        //     WebKit.DOM.DOMSelection selection = document.default_view.get_selection();
        //     WebKit.DOM.Node selection_base_node = selection.get_base_node();
        //     long selection_base_offset = selection.get_base_offset();

        //     WebKit.DOM.NodeList selection_child_nodes = selection_base_node.get_child_nodes();
        //     WebKit.DOM.Node ref_child = selection_child_nodes.item(selection_base_offset);

        //     WebKit.DOM.Element placeholder = document.create_element("SPAN");
        //     WebKit.DOM.Text placeholder_text = document.create_text_node("placeholder");
        //     placeholder.append_child(placeholder_text);

        //     if (selection_base_node.node_name == "#text") {
        //         WebKit.DOM.Node? left = get_left_text(selection_base_node, selection_base_offset);

        //         WebKit.DOM.Node parent = selection_base_node.parent_node;
        //         if (left != null)
        //             parent.insert_before(left, selection_base_node);
        //         parent.insert_before(placeholder, selection_base_node);
        //         parent.remove_child(selection_base_node);

        //         placeholder.scroll_into_view_if_needed(false);
        //         parent.insert_before(selection_base_node, placeholder);
        //         if (left != null)
        //             parent.remove_child(left);
        //         parent.remove_child(placeholder);
        //         selection.set_base_and_extent(selection_base_node, selection_base_offset, selection_base_node, selection_base_offset);
        //     } else {
        //         selection_base_node.insert_before(placeholder, ref_child);
        //         placeholder.scroll_into_view_if_needed(false);
        //         selection_base_node.remove_child(placeholder);
        //     }
        // } catch (Error err) {
        //     debug("Error scrolling pasted text into view: %s", err.message);
        // }
    }

    // private WebKit.DOM.Node? get_left_text(WebKit.WebPage page, WebKit.DOM.Node node, long offset) {
    //     WebKit.DOM.Document document = page.get_dom_document();
    //     string node_value = node.node_value;

    //     // Offset is in unicode characters, but index is in bytes. We need to get the corresponding
    //     // byte index for the given offset.
    //     int char_count = node_value.char_count();
    //     int index = offset > char_count ? node_value.length : node_value.index_of_nth_char(offset);

    //     return offset > 0 ? document.create_text_node(node_value[0:index]) : null;
    // }

    /**
     * Inserts some HTML at the current cursor location.
     */
    public void insert_html(string markup) {
        execute_editing_command_with_argument("insertHTML", markup);
    }

    /**
     * Sets whether the editor is in rich text or plain text mode.
     */
    public void set_rich_text(bool enabled) {
        this.is_rich_text = enabled;
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

    private void on_cursor_style_changed_message(WebKit.JavascriptResult result) {
        try {
            string[] values = WebKitUtil.to_string(result).split(",");
            string view_name = values[0].down();
            string? font_family = "sans";
            foreach (string name in ComposerWebView.font_family_map.keys) {
                if (name in view_name) {
                    font_family = ComposerWebView.font_family_map[name];
                    break;
                }
            }

            uint font_size = 12;
            values[1].scanf("%dpx", out font_size);

            cursor_style_changed(font_family, font_size);
        } catch (Geary.JS.Error err) {
            debug("Could not get cursor style: %s", err.message);
        } finally {
            result.unref();
        }
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
