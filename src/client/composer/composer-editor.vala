/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Widget for formatting and editing a message body.
 */
[GtkTemplate (ui = "/org/gnome/Geary/composer-editor.ui")]
public class ComposerEditor : Gtk.Grid {

    private const string BACKSPACE_TEXT = _("Press Backspace to delete quote");

    private const string ACTION_UNDO = "undo";
    private const string ACTION_REDO = "redo";
    private const string ACTION_CUT = "cut";
    private const string ACTION_COPY = "copy";
    private const string ACTION_COPY_LINK = "copy-link";
    private const string ACTION_PASTE = "paste";
    private const string ACTION_PASTE_WITH_FORMATTING = "paste-with-formatting";
    private const string ACTION_SELECT_ALL = "select-all";
    private const string ACTION_BOLD = "bold";
    private const string ACTION_ITALIC = "italic";
    private const string ACTION_UNDERLINE = "underline";
    private const string ACTION_STRIKETHROUGH = "strikethrough";
    private const string ACTION_FONT_SIZE = "font-size";
    private const string ACTION_FONT_FAMILY = "font-family";
    private const string ACTION_REMOVE_FORMAT = "remove-format";
    private const string ACTION_INDENT = "indent";
    private const string ACTION_OUTDENT = "outdent";
    private const string ACTION_JUSTIFY = "justify";
    private const string ACTION_COLOR = "color";
    private const string ACTION_INSERT_IMAGE = "insert-image";
    private const string ACTION_INSERT_LINK = "insert-link";
    // this is internal for Bug 771812 workaround in ComposerWidget
    internal const string ACTION_COMPOSE_AS_HTML = "compose-as-html";
    private const string ACTION_SELECT_DICTIONARY = "select-dictionary";
    private const string ACTION_OPEN_INSPECTOR = "open_inspector";

    // ACTION_INSERT_LINK and ACTION_REMOVE_FORMAT are missing from
    // here since they are handled in update_selection_actions
    private const string[] html_actions = {
        ACTION_BOLD, ACTION_ITALIC, ACTION_UNDERLINE, ACTION_STRIKETHROUGH,
        ACTION_FONT_SIZE, ACTION_FONT_FAMILY, ACTION_COLOR, ACTION_JUSTIFY,
        ACTION_INSERT_IMAGE, ACTION_COPY_LINK, ACTION_PASTE_WITH_FORMATTING
    };

    private const ActionEntry[] action_entries = {
        {ACTION_UNDO,                     on_undo                                       },
        {ACTION_REDO,                     on_redo                                       },
        {ACTION_CUT,                      on_cut                                        },
        {ACTION_COPY,                     on_copy                                       },
        {ACTION_COPY_LINK,                on_copy_link                                  },
        {ACTION_PASTE,                    on_paste                                      },
        {ACTION_PASTE_WITH_FORMATTING,    on_paste_with_formatting                      },
        {ACTION_SELECT_ALL,               on_select_all                                 },
        {ACTION_BOLD,                     on_action,                null,      "false"  },
        {ACTION_ITALIC,                   on_action,                null,      "false"  },
        {ACTION_UNDERLINE,                on_action,                null,      "false"  },
        {ACTION_STRIKETHROUGH,            on_action,                null,      "false"  },
        {ACTION_FONT_SIZE,                on_font_size,              "s",   "'medium'"  },
        {ACTION_FONT_FAMILY,              on_font_family,            "s",     "'sans'"  },
        {ACTION_REMOVE_FORMAT,            on_remove_format,         null,      "false"  },
        {ACTION_INDENT,                   on_indent                                     },
        {ACTION_OUTDENT,                  on_action                                     },
        {ACTION_JUSTIFY,                  on_justify,                "s",     "'left'"  },
        {ACTION_COLOR,                    on_select_color                               },
        {ACTION_INSERT_IMAGE,             on_insert_image                               },
        {ACTION_INSERT_LINK,              on_insert_link                                },
        {ACTION_COMPOSE_AS_HTML,          on_toggle_action,        null,   "true",  on_compose_as_html_toggled },
        {ACTION_SELECT_DICTIONARY,        on_select_dictionary                                                 },
        {ACTION_OPEN_INSPECTOR,           on_open_inspector                                                    }
    };

    public static Gee.MultiMap<string, string> action_accelerators = new Gee.HashMultiMap<string, string>();
    static construct {
        action_accelerators.set(ACTION_UNDO, "<Ctrl>z");
        action_accelerators.set(ACTION_REDO, "<Ctrl><Shift>z");
        action_accelerators.set(ACTION_CUT, "<Ctrl>x");
        action_accelerators.set(ACTION_COPY, "<Ctrl>c");
        action_accelerators.set(ACTION_PASTE, "<Ctrl>v");
        action_accelerators.set(ACTION_PASTE_WITH_FORMATTING, "<Ctrl><Shift>v");
        action_accelerators.set(ACTION_INSERT_IMAGE, "<Ctrl>g");
        action_accelerators.set(ACTION_INSERT_LINK, "<Ctrl>l");
        action_accelerators.set(ACTION_INDENT, "<Ctrl>bracketright");
        action_accelerators.set(ACTION_OUTDENT, "<Ctrl>bracketleft");
        action_accelerators.set(ACTION_REMOVE_FORMAT, "<Ctrl>space");
        action_accelerators.set(ACTION_BOLD, "<Ctrl>b");
        action_accelerators.set(ACTION_ITALIC, "<Ctrl>i");
        action_accelerators.set(ACTION_UNDERLINE, "<Ctrl>u");
        action_accelerators.set(ACTION_STRIKETHROUGH, "<Ctrl>k");
    }

    /** Determines if the view is in rich text mode. */
    public bool is_rich_text { get; private set; default = true; }

    /** The HTML editor for the message's body text. */
    public ComposerWebView body { get; private set; }

    // this is internal for Bug 771812 workaround in ComposerWidget
    internal SimpleActionGroup actions = new SimpleActionGroup();

    private Configuration config { get; set; }

    private bool can_delete_quote { get; private set; default = false; }

    [GtkChild]
    private Gtk.Grid body_container;

    [GtkChild]
    private Gtk.Box composer_toolbar;
    [GtkChild]
    private Gtk.Box insert_buttons;
    [GtkChild]
    private Gtk.Box font_style_buttons;
    [GtkChild]
    private Gtk.Button insert_link_button;
    [GtkChild]
    private Gtk.Button remove_format_button;
    [GtkChild]
    private Gtk.Button select_dictionary_button;
    [GtkChild]
    private Gtk.MenuButton menu_button;
    [GtkChild]
    private Gtk.Label info_label;
    [GtkChild]
    private Gtk.Label message_overlay_label;

    [GtkChild]
    private Gtk.Box message_area;

    private Menu html_menu;
    private Menu plain_menu;

    private Menu context_menu_model;
    private Menu context_menu_rich_text;
    private Menu context_menu_plain_text;
    private Menu context_menu_webkit_spelling;
    private Menu context_menu_webkit_text_entry;
    private Menu context_menu_inspector;

    private SpellCheckPopover? spell_check_popover = null;
    private string? pointer_url = null;
    private string? cursor_url = null;

    /** Fired when the user opens a link in the composer. */
    public signal void link_activated(string url);

    /** Fired when the user invokes the insert image action. */
    public signal void insert_image();


    public ComposerEditor(Configuration config) {
        this.config = config;
        this.body = new ComposerWebView(config);
        this.body.set_hexpand(true);
        this.body.set_vexpand(true);
        this.body.show();

        this.body_container.add(this.body);

        // Initialize menus
        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/composer-menus.ui"
        );
        this.html_menu = (Menu) builder.get_object("html_menu_model");
        this.plain_menu = (Menu) builder.get_object("plain_menu_model");
        this.context_menu_model = (Menu) builder.get_object("context_menu_model");
        this.context_menu_rich_text = (Menu) builder.get_object("context_menu_rich_text");
        this.context_menu_plain_text = (Menu) builder.get_object("context_menu_plain_text");
        this.context_menu_inspector = (Menu) builder.get_object("context_menu_inspector");
        this.context_menu_webkit_spelling = (Menu) builder.get_object("context_menu_webkit_spelling");
        this.context_menu_webkit_text_entry = (Menu) builder.get_object("context_menu_webkit_text_entry");

        // Add actions once every element has been initialized and added
        this.actions.add_action_entries(action_entries, this);

        insert_action_group("cpe", this.actions);
        get_action(ACTION_UNDO).set_enabled(false);
        get_action(ACTION_REDO).set_enabled(false);
        update_cursor_actions();

        this.body.command_stack_changed.connect(on_command_state_changed);
        this.body.button_release_event_done.connect(on_button_release);
        this.body.context_menu.connect(on_context_menu);
        this.body.cursor_context_changed.connect(on_cursor_context_changed);
        this.body.get_editor_state().notify["typing-attributes"].connect(on_typing_attributes_changed);
        this.body.key_press_event.connect(on_editor_key_press_event);
        this.body.load_changed.connect(on_load_changed);
        this.body.mouse_target_changed.connect(on_mouse_target_changed);
        this.body.selection_changed.connect(on_selection_changed);

        // Place the message area before the compose toolbar in the
        // focus chain, so that the user can tab directly from the
        // Subject: field to the message area.  TODO: after bumping
        // the min. GTK+ version to 3.16, we can/should do this in the
        // UI file.
        List<Gtk.Widget> chain = new List<Gtk.Widget>();
        chain.append(this.message_area);
        chain.append(this.composer_toolbar);
        set_focus_chain(chain);
    }

    /**
     * Enables deleting the quote a reply is first loaded.
     */
    public void enable_quote_delete() {
        this.can_delete_quote = true;
        set_info_text(BACKSPACE_TEXT);
    }

    /**
     * Sets informational text shown to the user on the toolbar.
     */
    public void set_info_text(string info) {
        this.info_label.set_text(info);
    }

    private void update_cursor_actions() {
        bool has_selection = this.body.has_selection;
        get_action(ACTION_CUT).set_enabled(has_selection);
        get_action(ACTION_COPY).set_enabled(has_selection);

        get_action(ACTION_INSERT_LINK).set_enabled(
            this.is_rich_text && (has_selection || this.cursor_url != null)
        );
        get_action(ACTION_REMOVE_FORMAT).set_enabled(
            this.is_rich_text && has_selection
        );
    }

    private async ComposerLinkPopover new_link_popover(ComposerLinkPopover.Type type,
                                                       string url) {
        var selection_id = "";
        try {
            selection_id = yield this.body.save_selection();
        } catch (Error err) {
            debug("Error saving selection: %s", err.message);
        }
        ComposerLinkPopover popover = new ComposerLinkPopover(type);
        popover.set_link_url(url);
        popover.closed.connect(() => {
                this.body.free_selection(selection_id);
                Idle.add(() => { popover.destroy(); return Source.REMOVE; });
            });
        popover.link_activate.connect((link_uri) => {
                this.body.insert_link(popover.link_uri, selection_id);
            });
        popover.link_delete.connect(() => {
                this.body.delete_link();
            });
        popover.link_open.connect(() => { link_activated(popover.link_uri); });
        return popover;
    }

    private SimpleAction? get_action(string action_name) {
        return this.actions.lookup_action(action_name) as SimpleAction;
    }

    private void on_load_changed(WebKit.WebView view, WebKit.LoadEvent event) {
        if (event == WebKit.LoadEvent.FINISHED) {
            if (get_realized())
                on_load_finished_and_realized();
            else
                realize.connect(on_load_finished_and_realized);
        }
    }

    private void on_load_finished_and_realized() {
        // This is safe to call even when this connection hasn't been made.
        realize.disconnect(on_load_finished_and_realized);

        this.actions.change_action_state(
            ACTION_COMPOSE_AS_HTML, this.config.compose_as_html
        );

        if (this.can_delete_quote) {
            // Would be nice to clean this up an bit.
            this.notify["can-delete-quote"].connect(() => {
                    if (this.info_label.get_text() == BACKSPACE_TEXT) {
                        set_info_text("");
                    }
                });
            this.body.selection_changed.connect(
                () => { this.can_delete_quote = false; }
            );
        }
    }

    private void on_action(SimpleAction action, Variant? param) {
        if (!action.enabled)
            return;

        // We need the unprefixed name to send as a command to the editor
        string[] prefixed_action_name = action.get_name().split(".");
        string action_name = prefixed_action_name[prefixed_action_name.length - 1];
        this.body.execute_editing_command(action_name);
    }

    // Use this for toggle actions, and use the change-state signal to respond to these state changes
    private void on_toggle_action(SimpleAction? action, Variant? param) {
        action.change_state(!action.state.get_boolean());
    }

    private void on_compose_as_html_toggled(SimpleAction? action, Variant? new_state) {
        bool compose_as_html = new_state.get_boolean();
        action.set_state(compose_as_html);

        foreach (string html_action in html_actions)
            get_action(html_action).set_enabled(compose_as_html);

        update_cursor_actions();

        this.insert_buttons.visible = compose_as_html;
        this.font_style_buttons.visible = compose_as_html;
        this.remove_format_button.visible = compose_as_html;

        this.menu_button.menu_model = (compose_as_html) ? this.html_menu : this.plain_menu;

        this.is_rich_text = compose_as_html;
        this.body.set_rich_text(compose_as_html);

        this.config.compose_as_html = compose_as_html;
    }

    private void on_undo(SimpleAction action, Variant? param) {
        this.body.undo();
    }

    private void on_redo(SimpleAction action, Variant? param) {
        this.body.redo();
    }

    private void on_cut(SimpleAction action, Variant? param) {
        this.body.cut_clipboard();
    }

    private void on_copy(SimpleAction action, Variant? param) {
        this.body.copy_clipboard();
    }

    private void on_copy_link(SimpleAction action, Variant? param) {
        Gtk.Clipboard c = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        // XXX could this also be the cursor URL? We should be getting
        // the target URL as from the action param
        c.set_text(this.pointer_url, -1);
        c.store();
    }

    private void on_paste(SimpleAction action, Variant? param) {
        this.body.paste_plain_text();
    }

    private void on_paste_with_formatting(SimpleAction action, Variant? param) {
        this.body.paste_rich_text();
    }

    private void on_select_all(SimpleAction action, Variant? param) {
        this.body.select_all();
    }

    private void on_remove_format(SimpleAction action, Variant? param) {
        this.body.execute_editing_command("removeformat");
        this.body.execute_editing_command("removeparaformat");
        this.body.execute_editing_command("unlink");
        this.body.execute_editing_command_with_argument("backcolor", "#ffffff");
        this.body.execute_editing_command_with_argument("forecolor", "#000000");
    }

    private void on_indent(SimpleAction action, Variant? param) {
        this.body.indent_line();
    }

    private void on_justify(SimpleAction action, Variant? param) {
        this.body.execute_editing_command("justify" + param.get_string());
    }

    private void on_font_family(SimpleAction action, Variant? param) {
        this.body.execute_editing_command_with_argument(
            "fontname", param.get_string()
        );
        action.set_state(param.get_string());
    }

    private void on_font_size(SimpleAction action, Variant? param) {
        string size = "";
        if (param.get_string() == "small")
            size = "1";
        else if (param.get_string() == "medium")
            size = "3";
        else // Large
            size = "7";

        this.body.execute_editing_command_with_argument("fontsize", size);
        action.set_state(param.get_string());
    }

    private void on_select_color() {
        Gtk.ColorChooserDialog dialog = new Gtk.ColorChooserDialog(
            _("Select Color"), get_toplevel() as Gtk.Window
        );
        if (dialog.run() == Gtk.ResponseType.OK) {
            this.body.execute_editing_command_with_argument(
                "forecolor", dialog.get_rgba().to_string()
            );
        }
        dialog.destroy();
    }

    private void on_mouse_target_changed(WebKit.WebView web_view,
                                         WebKit.HitTestResult hit_test,
                                         uint modifiers) {
        bool copy_link_enabled = hit_test.context_is_link();
        this.pointer_url = copy_link_enabled ? hit_test.get_link_uri() : null;
        this.message_overlay_label.label = this.pointer_url ?? "";
        get_action(ACTION_COPY_LINK).set_enabled(copy_link_enabled);
    }

    private void update_message_overlay_label_style() {
        Gtk.Window? window = get_toplevel() as Gtk.Window;
        if (window != null) {
            Gdk.RGBA window_background = window.get_style_context()
                .get_background_color(Gtk.StateFlags.NORMAL);
            Gdk.RGBA label_background = this.message_overlay_label.get_style_context()
                .get_background_color(Gtk.StateFlags.NORMAL);

            if (label_background == window_background)
                return;

            message_overlay_label.get_style_context().changed.disconnect(
                on_message_overlay_label_style_changed);
            message_overlay_label.override_background_color(Gtk.StateFlags.NORMAL, window_background);
            message_overlay_label.get_style_context().changed.connect(
                on_message_overlay_label_style_changed);
        }
    }

    [GtkCallback]
    private void on_message_overlay_label_realize() {
        update_message_overlay_label_style();
    }

    private void on_message_overlay_label_style_changed() {
        update_message_overlay_label_style();
    }

    private bool on_context_menu(WebKit.WebView view,
                                 WebKit.ContextMenu context_menu,
                                 Gdk.Event event,
                                 WebKit.HitTestResult hit_test_result) {
        // This is a three step process:
        // 1. Work out what existing menu items exist that we want to keep
        // 2. Clear the existing menu
        // 3. Rebuild it based on our GMenu specification

        // Step 1.

        const WebKit.ContextMenuAction[] SPELLING_ACTIONS = {
            WebKit.ContextMenuAction.SPELLING_GUESS,
            WebKit.ContextMenuAction.NO_GUESSES_FOUND,
            WebKit.ContextMenuAction.IGNORE_SPELLING,
            WebKit.ContextMenuAction.IGNORE_GRAMMAR,
            WebKit.ContextMenuAction.LEARN_SPELLING,
        };
        const WebKit.ContextMenuAction[] TEXT_INPUT_ACTIONS = {
            WebKit.ContextMenuAction.INPUT_METHODS,
            WebKit.ContextMenuAction.UNICODE,
        };

        Gee.List<WebKit.ContextMenuItem> existing_spelling =
            new Gee.LinkedList<WebKit.ContextMenuItem>();
        Gee.List<WebKit.ContextMenuItem> existing_text_entry =
            new Gee.LinkedList<WebKit.ContextMenuItem>();

        foreach (WebKit.ContextMenuItem item in context_menu.get_items()) {
            if (item.get_stock_action() in SPELLING_ACTIONS) {
                existing_spelling.add(item);
            } else if (item.get_stock_action() in TEXT_INPUT_ACTIONS) {
                existing_text_entry.add(item);
            }
        }

        // Step 2.

        context_menu.remove_all();

        // Step 3.

        GtkUtil.menu_foreach(context_menu_model, (label, name, target, section) => {
                if (context_menu.last() != null) {
                    context_menu.append(new WebKit.ContextMenuItem.separator());
                }

                if (section == this.context_menu_webkit_spelling) {
                    foreach (WebKit.ContextMenuItem item in existing_spelling)
                        context_menu.append(item);
                } else if (section == this.context_menu_webkit_text_entry) {
                    foreach (WebKit.ContextMenuItem item in existing_text_entry)
                        context_menu.append(item);
                } else if (section == this.context_menu_rich_text) {
                    if (this.is_rich_text)
                        append_menu_section(context_menu, section);
                } else if (section == this.context_menu_plain_text) {
                    if (!this.is_rich_text)
                        append_menu_section(context_menu, section);
                } else if (section == this.context_menu_inspector) {
                    if (Args.inspector)
                        append_menu_section(context_menu, section);
                } else {
                    append_menu_section(context_menu, section);
                }
            });

        // 4. Update the clipboard
        // get_clipboard(Gdk.SELECTION_CLIPBOARD).request_targets(
        //     (_, targets) => {
        //         foreach (Gdk.Atom atom in targets) {
        //             debug("atom name: %s", atom.name());
        //         }
        //     });

        return Gdk.EVENT_PROPAGATE;
    }

    private inline void append_menu_section(WebKit.ContextMenu context_menu,
                                            Menu section) {
        GtkUtil.menu_foreach(section, (label, name, target, section) => {
                if ("." in name)
                    name = name.split(".")[1];

                Gtk.Action action = new Gtk.Action(name, label, null, null);
                action.set_sensitive(get_action(name).enabled);
                action.activate.connect((action) => {
                        this.actions.activate_action(name, target);
                    });
                context_menu.append(new WebKit.ContextMenuItem(action));
            });
    }

    private void on_select_dictionary(SimpleAction action, Variant? param) {
        if (this.spell_check_popover == null) {
            this.spell_check_popover = new SpellCheckPopover(
                this.select_dictionary_button, this.config
            );
            this.spell_check_popover.selection_changed.connect((active_langs) => {
                    this.config.spell_check_languages = active_langs;
                });
        }
        this.spell_check_popover.toggle();
    }

    private bool on_editor_key_press_event(Gdk.EventKey event) {
        if (this.can_delete_quote) {
            this.can_delete_quote = false;
            if (event.is_modifier == 0 &&
                event.keyval == Gdk.Key.BackSpace) {
                this.body.delete_quoted_message();
                return Gdk.EVENT_STOP;
            }
        }

        return Gdk.EVENT_PROPAGATE;
    }

    private void on_command_state_changed(bool can_undo, bool can_redo) {
        get_action(ACTION_UNDO).set_enabled(can_undo);
        get_action(ACTION_REDO).set_enabled(can_redo);
    }

    private bool on_button_release(Gdk.Event event) {
        // Show the link popover on mouse release (instead of press)
        // so the user can still select text with a link in it,
        // without the popover immediately appearing and raining on
        // their text selection parade.
        if (this.pointer_url != null &&
            this.actions.get_action_state(ACTION_COMPOSE_AS_HTML).get_boolean()) {
            Gdk.EventButton? button = (Gdk.EventButton) event;
            Gdk.Rectangle location = new Gdk.Rectangle();
            location.x = (int) button.x;
            location.y = (int) button.y;

            this.new_link_popover.begin(
                ComposerLinkPopover.Type.EXISTING_LINK, this.pointer_url,
                (obj, res) => {
                    ComposerLinkPopover popover = this.new_link_popover.end(res);
                    popover.set_relative_to(this.body);
                    popover.set_pointing_to(location);
                    popover.show();
                });
        }
        return Gdk.EVENT_PROPAGATE;
    }

    private void on_cursor_context_changed(ComposerWebView.EditContext context) {
        this.cursor_url = context.is_link ? context.link_url : null;
        update_cursor_actions();

        this.actions.change_action_state(ACTION_FONT_FAMILY, context.font_family);

        if (context.font_size < 11)
            this.actions.change_action_state(ACTION_FONT_SIZE, "small");
        else if (context.font_size > 20)
            this.actions.change_action_state(ACTION_FONT_SIZE, "large");
        else
            this.actions.change_action_state(ACTION_FONT_SIZE, "medium");
    }

    private void on_typing_attributes_changed() {
        uint mask = this.body.get_editor_state().get_typing_attributes();
        this.actions.change_action_state(
            ACTION_BOLD,
            (mask & WebKit.EditorTypingAttributes.BOLD) == WebKit.EditorTypingAttributes.BOLD
        );
        this.actions.change_action_state(
            ACTION_ITALIC,
            (mask & WebKit.EditorTypingAttributes.ITALIC) == WebKit.EditorTypingAttributes.ITALIC
        );
        this.actions.change_action_state(
            ACTION_UNDERLINE,
            (mask & WebKit.EditorTypingAttributes.UNDERLINE) == WebKit.EditorTypingAttributes.UNDERLINE
        );
        this.actions.change_action_state(
            ACTION_STRIKETHROUGH,
            (mask & WebKit.EditorTypingAttributes.STRIKETHROUGH) == WebKit.EditorTypingAttributes.STRIKETHROUGH
        );
    }

    private void on_insert_image(SimpleAction action, Variant? param) {
        insert_image();
    }

    private void on_insert_link(SimpleAction action, Variant? param) {
        ComposerLinkPopover.Type type = ComposerLinkPopover.Type.NEW_LINK;
        string url = "http://";
        if (this.cursor_url != null) {
            type = ComposerLinkPopover.Type.EXISTING_LINK;
            url = this.cursor_url;
        }

        this.new_link_popover.begin(type, url, (obj, res) => {
                ComposerLinkPopover popover = this.new_link_popover.end(res);

                // We have to disconnect then reconnect the selection
                // changed signal for the duration of the popover
                // being active since if the user selects the text in
                // the URL entry, then the editor will lose its
                // selection, the inset link action will become
                // disabled, and the popover will disappear
                this.body.selection_changed.disconnect(on_selection_changed);
                popover.closed.connect(() => {
                        this.body.selection_changed.connect(on_selection_changed);
                    });

                popover.set_relative_to(this.insert_link_button);
                popover.show();
            });
    }

    private void on_open_inspector(SimpleAction action, Variant? param) {
        this.body.get_inspector().show();
    }

    private void on_selection_changed(bool has_selection) {
        update_cursor_actions();
    }

}
