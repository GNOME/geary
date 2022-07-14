/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2017-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[CCode (cname = "components_reflow_box_get_type")]
private extern Type components_reflow_box_get_type();

/**
 * A widget for editing the body of an email message.
 */
[GtkTemplate (ui = "/org/gnome/Geary/composer-editor.ui")]
public class Composer.Editor : Gtk.Grid, Geary.BaseInterface {

    private const string ACTION_BOLD = "bold";
    private const string ACTION_COLOR = "color";
    private const string ACTION_COPY_LINK = "copy-link";
    private const string ACTION_CUT = "cut";
    private const string ACTION_FONT_FAMILY = "font-family";
    private const string ACTION_FONT_SIZE = "font-size";
    private const string ACTION_INDENT = "indent";
    private const string ACTION_INSERT_IMAGE = "insert-image";
    private const string ACTION_INSERT_LINK = "insert-link";
    private const string ACTION_ITALIC = "italic";
    private const string ACTION_JUSTIFY = "justify";
    private const string ACTION_OLIST = "olist";
    private const string ACTION_OPEN_INSPECTOR = "open_inspector";
    private const string ACTION_OUTDENT = "outdent";
    private const string ACTION_PASTE = "paste";
    private const string ACTION_PASTE_WITHOUT_FORMATTING = "paste-without-formatting";
    private const string ACTION_REMOVE_FORMAT = "remove-format";
    private const string ACTION_SELECT_ALL = "select-all";
    private const string ACTION_SELECT_DICTIONARY = "select-dictionary";
    private const string ACTION_SHOW_FORMATTING = "show-formatting";
    private const string ACTION_STRIKETHROUGH = "strikethrough";
    internal const string ACTION_TEXT_FORMAT = "text-format";
    private const string ACTION_ULIST = "ulist";
    private const string ACTION_UNDERLINE = "underline";

    // ACTION_INSERT_LINK and ACTION_REMOVE_FORMAT are missing from
    // here since they are handled in update_selection_actions
    private const string[] HTML_ACTIONS = {
        ACTION_BOLD, ACTION_ITALIC, ACTION_UNDERLINE, ACTION_STRIKETHROUGH,
        ACTION_FONT_SIZE, ACTION_FONT_FAMILY, ACTION_COLOR, ACTION_JUSTIFY,
        ACTION_INSERT_IMAGE, ACTION_COPY_LINK,
        ACTION_OLIST, ACTION_ULIST
    };

    private const ActionEntry[] ACTIONS = {
        { Action.Edit.COPY,                on_copy                            },
        { Action.Edit.REDO,                on_redo                            },
        { Action.Edit.UNDO,                on_undo                            },
        { ACTION_BOLD,                     on_action,        null, "false"    },
        { ACTION_COLOR,                    on_select_color                    },
        { ACTION_COPY_LINK,                on_copy_link                       },
        { ACTION_CUT,                      on_cut                             },
        { ACTION_FONT_FAMILY,              on_font_family,   "s",  "'sans'"   },
        { ACTION_FONT_SIZE,                on_font_size,     "s",  "'medium'" },
        { ACTION_INDENT,                   on_indent                          },
        { ACTION_INSERT_IMAGE,             on_insert_image                    },
        { ACTION_INSERT_LINK,              on_insert_link                     },
        { ACTION_ITALIC,                   on_action,        null, "false"    },
        { ACTION_JUSTIFY,                  on_justify,       "s",  "'left'"   },
        { ACTION_OLIST,                    on_olist                           },
        { ACTION_OPEN_INSPECTOR,           on_open_inspector                  },
        { ACTION_OUTDENT,                  on_action                          },
        { ACTION_PASTE,                    on_paste                           },
        { ACTION_PASTE_WITHOUT_FORMATTING, on_paste_without_formatting        },
        { ACTION_REMOVE_FORMAT,            on_remove_format, null, "false"    },
        { ACTION_SELECT_ALL,               on_select_all                      },
        { ACTION_SELECT_DICTIONARY,        on_select_dictionary              },
        { ACTION_SHOW_FORMATTING,          on_toggle_action, null, "false",
                                           on_show_formatting                 },
        { ACTION_STRIKETHROUGH,            on_action,        null, "false"    },
        { ACTION_TEXT_FORMAT,              null,             "s", "'html'",
                                           on_text_format                     },
        { ACTION_ULIST,                    on_ulist                           },
        { ACTION_UNDERLINE,                on_action,        null, "false"    },
    };


    static construct {
        set_css_name("geary-composer-editor");
    }

    public static void add_accelerators(Application.Client application) {
        application.add_edit_accelerators(ACTION_CUT, { "<Ctrl>x" } );
        application.add_edit_accelerators(ACTION_PASTE, { "<Ctrl>v" } );
        application.add_edit_accelerators(ACTION_PASTE_WITHOUT_FORMATTING, { "<Ctrl><Shift>v" } );
        application.add_edit_accelerators(ACTION_INSERT_IMAGE, { "<Ctrl>g" } );
        application.add_edit_accelerators(ACTION_INSERT_LINK, { "<Ctrl>l" } );
        application.add_edit_accelerators(ACTION_INDENT, { "<Ctrl>bracketright" } );
        application.add_edit_accelerators(ACTION_OUTDENT, { "<Ctrl>bracketleft" } );
        application.add_edit_accelerators(ACTION_REMOVE_FORMAT, { "<Ctrl>space" } );
        application.add_edit_accelerators(ACTION_BOLD, { "<Ctrl>b" } );
        application.add_edit_accelerators(ACTION_ITALIC, { "<Ctrl>i" } );
        application.add_edit_accelerators(ACTION_UNDERLINE, { "<Ctrl>u" } );
        application.add_edit_accelerators(ACTION_STRIKETHROUGH, { "<Ctrl>k" } );
    }


    /** The email body view. */
    public WebView body { get; private set; }

    internal GLib.SimpleActionGroup actions = new GLib.SimpleActionGroup();

    [GtkChild] internal unowned Gtk.Button new_message_attach_button;
    [GtkChild] internal unowned Gtk.Box conversation_attach_buttons;

    private Application.Configuration config;

    private string? pointer_url = null;
    private string? cursor_url = null;

    // Timeout for showing the slow image paste pulsing bar
    private Geary.TimeoutManager show_background_work_timeout = null;
    // Timer for pulsing progress bar
    private Geary.TimeoutManager background_work_pulse;

    private Menu context_menu_model;
    private Menu context_menu_rich_text;
    private Menu context_menu_plain_text;
    private Menu context_menu_webkit_spelling;
    private Menu context_menu_webkit_text_entry;
    private Menu context_menu_inspector;

    [GtkChild] private unowned Gtk.Grid body_container;

    [GtkChild] private unowned Gtk.Label message_overlay_label;

    [GtkChild] private unowned Gtk.Box action_bar_box;

    [GtkChild] private unowned Gtk.Button insert_link_button;
    [GtkChild] private unowned Gtk.MenuButton select_dictionary_button;

    [GtkChild] private unowned Gtk.Label info_label;

    [GtkChild] private unowned Gtk.ProgressBar background_progress;

    [GtkChild] private unowned Gtk.Revealer formatting;
    [GtkChild] private unowned Gtk.MenuButton font_button;
    [GtkChild] private unowned Gtk.Stack font_button_stack;
    [GtkChild] private unowned Gtk.MenuButton font_size_button;
    [GtkChild] private unowned Gtk.Image font_color_icon;
    [GtkChild] private unowned Gtk.MenuButton more_options_button;

    private Gtk.GestureMultiPress click_gesture;


    internal signal void insert_image(bool from_clipboard);


    internal Editor(Application.Configuration config) {
        base_ref();
        components_reflow_box_get_type();
        this.config = config;

        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/composer-editor-menus.ui"
        );
        this.context_menu_model = (Menu) builder.get_object("context_menu_model");
        this.context_menu_rich_text = (Menu) builder.get_object("context_menu_rich_text");
        this.context_menu_plain_text = (Menu) builder.get_object("context_menu_plain_text");
        this.context_menu_inspector = (Menu) builder.get_object("context_menu_inspector");
        this.context_menu_webkit_spelling = (Menu) builder.get_object("context_menu_webkit_spelling");
        this.context_menu_webkit_text_entry = (Menu) builder.get_object("context_menu_webkit_text_entry");

        this.body = new WebView(config);
        this.body.command_stack_changed.connect(on_command_state_changed);
        this.body.context_menu.connect(on_context_menu);
        this.body.cursor_context_changed.connect(on_cursor_context_changed);
        this.body.get_editor_state().notify["typing-attributes"].connect(on_typing_attributes_changed);
        this.body.mouse_target_changed.connect(on_mouse_target_changed);
        this.body.notify["has-selection"].connect(on_selection_changed);
        this.body.set_hexpand(true);
        this.body.set_vexpand(true);
        this.body.show();
        this.body_container.add(this.body);

        this.click_gesture = new Gtk.GestureMultiPress(this.body);
        this.click_gesture.propagation_phase = CAPTURE;
        this.click_gesture.pressed.connect(this.on_button_press);
        this.click_gesture.released.connect(this.on_button_release);

        this.actions.add_action_entries(ACTIONS, this);
        this.actions.change_action_state(
            ACTION_TEXT_FORMAT,
            config.compose_as_html ? "html" : "plain"
        );
        this.actions.change_action_state(
            ACTION_SHOW_FORMATTING,
            config.formatting_toolbar_visible
        );
        insert_action_group(Action.Edit.GROUP_NAME, this.actions);
        get_action(Action.Edit.UNDO).set_enabled(false);
        get_action(Action.Edit.REDO).set_enabled(false);
        update_cursor_actions();

        var spell_check_popover = new SpellCheckPopover(
            this.select_dictionary_button, config
        );
        spell_check_popover.selection_changed.connect((active_langs) => {
            config.set_spell_check_languages(active_langs);
        });

        this.show_background_work_timeout = new Geary.TimeoutManager.milliseconds(
            Util.Gtk.SHOW_PROGRESS_TIMEOUT_MSEC, this.on_background_work_timeout
        );
        this.background_work_pulse = new Geary.TimeoutManager.milliseconds(
            Util.Gtk.PROGRESS_PULSE_TIMEOUT_MSEC, this.background_progress.pulse
        );
        this.background_work_pulse.repetition = FOREVER;
    }

    ~Editor() {
        base_unref();
    }

    public override void destroy() {
        this.show_background_work_timeout.reset();
        this.background_work_pulse.reset();
        base.destroy();
    }

    /** Adds an action bar to the composer. */
    public void add_action_bar(Gtk.ActionBar to_add) {
        this.action_bar_box.pack_start(to_add);
        this.action_bar_box.reorder_child(to_add, 0);
    }

    /**
     * Inserts a menu section into the editor's menu.
     */
    public void insert_menu_section(GLib.MenuModel section) {
        var menu = this.more_options_button.menu_model as GLib.Menu;
        if (menu != null) {
            menu.insert_section(0, null, section);
        }
    }

    /** Displays the given human readable text in the UI */
    internal void set_info_label(string text) {
        this.info_label.set_text(text);
        this.info_label.set_tooltip_text(text);
    }

    /** Starts the progress meter timer. */
    internal void start_background_work_pulse() {
        this.show_background_work_timeout.start();
    }

    /** Hides and stops pulsing the progress meter. */
    internal void stop_background_work_pulse() {
        this.background_progress.hide();
        this.background_work_pulse.reset();
        this.show_background_work_timeout.reset();
    }

    private void update_cursor_actions() {
        bool has_selection = this.body.has_selection;
        get_action(ACTION_CUT).set_enabled(has_selection);
        get_action(Action.Edit.COPY).set_enabled(has_selection);

        get_action(ACTION_INSERT_LINK).set_enabled(
            this.body.is_rich_text && (has_selection || this.cursor_url != null)
        );
        get_action(ACTION_REMOVE_FORMAT).set_enabled(
            this.body.is_rich_text && has_selection
        );
    }

    private async LinkPopover new_link_popover(LinkPopover.Type type,
                                               string url) {
        var selection_id = "";
        try {
            selection_id = yield this.body.save_selection();
        } catch (Error err) {
            debug("Error saving selection: %s", err.message);
        }
        LinkPopover popover = new LinkPopover(type);
        popover.set_link_url(url);
        popover.closed.connect(() => {
                this.body.free_selection(selection_id);
            });
        popover.hide.connect(() => {
                Idle.add(() => { popover.destroy(); return Source.REMOVE; });
            });
        popover.link_activate.connect((link_uri) => {
                this.body.insert_link(popover.link_uri, selection_id);
            });
        popover.link_delete.connect(() => {
                this.body.delete_link(selection_id);
            });
        return popover;
    }

    private void update_formatting_toolbar() {
        var show_formatting = (SimpleAction) this.actions.lookup_action(ACTION_SHOW_FORMATTING);
        var text_format = (SimpleAction) this.actions.lookup_action(ACTION_TEXT_FORMAT);
        this.formatting.reveal_child = text_format.get_state().get_string() == "html" && show_formatting.get_state().get_boolean();
    }

    private async void update_color_icon(Gdk.RGBA color) {
        var theme = Gtk.IconTheme.get_default();
        var icon = theme.lookup_icon("font-color-symbolic", 16, 0);
        var fg_color = Util.Gtk.rgba(0, 0, 0, 1);
        this.get_style_context().lookup_color("theme_fg_color", out fg_color);

        try {
            var pixbuf = yield icon.load_symbolic_async(
                fg_color, color, null, null, null
            );
            this.font_color_icon.pixbuf = pixbuf;
        } catch(Error e) {
            warning("Could not load icon `font-color-symbolic`!");
            this.font_color_icon.icon_name = "font-color-symbolic";
        }
    }

    private GLib.SimpleAction? get_action(string action_name) {
        return this.actions.lookup_action(action_name) as GLib.SimpleAction;
    }

    private void on_button_press(int n_press, double x, double y) {
        this.body.grab_focus();
    }

    private void on_button_release(int n_press, double x, double y) {
        // Show the link popover on mouse release (instead of press)
        // so the user can still select text with a link in it,
        // without the popover immediately appearing and raining on
        // their text selection parade.
        if (this.pointer_url != null &&
            this.config.compose_as_html) {
            Gdk.Rectangle location = Gdk.Rectangle();
            location.x = (int) x;
            location.y = (int) y;

            this.new_link_popover.begin(
                LinkPopover.Type.EXISTING_LINK, this.pointer_url,
                (obj, res) => {
                    LinkPopover popover = this.new_link_popover.end(res);
                    popover.set_relative_to(this.body);
                    popover.set_pointing_to(location);
                    popover.popup();
                });
        }
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
            WebKit.ContextMenuAction.INSERT_EMOJI,
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

        Util.Gtk.menu_foreach(
            this.context_menu_model,
            (label, name, target, section) => {
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
                    if (this.body.is_rich_text)
                        append_menu_section(context_menu, section);
                } else if (section == this.context_menu_plain_text) {
                    if (!this.body.is_rich_text)
                        append_menu_section(context_menu, section);
                } else if (section == this.context_menu_inspector) {
                    if (this.config.enable_inspector)
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
        Util.Gtk.menu_foreach(section, (label, name, target, section) => {
                string simple_name = name;
                if ("." in simple_name) {
                    simple_name = simple_name.split(".")[1];
                }

                GLib.SimpleAction? action = get_action(simple_name);
                if (action != null) {
                    context_menu.append(
                        new WebKit.ContextMenuItem.from_gaction(
                            action, label, target
                        )
                    );
                } else {
                    warning("Unknown action: %s/%s", name, label);
                }
            });
    }

    private void on_cursor_context_changed(WebView.EditContext context) {
        this.cursor_url = context.is_link ? context.link_url : null;
        update_cursor_actions();

        this.actions.change_action_state(
            ACTION_FONT_FAMILY, context.font_family
        );

        this.update_color_icon.begin(context.font_color);

        if (context.font_size < 11)
            this.actions.change_action_state(ACTION_FONT_SIZE, "small");
        else if (context.font_size > 20)
            this.actions.change_action_state(ACTION_FONT_SIZE, "large");
        else
            this.actions.change_action_state(ACTION_FONT_SIZE, "medium");
    }

    private void on_mouse_target_changed(WebKit.WebView web_view,
                                         WebKit.HitTestResult hit_test,
                                         uint modifiers) {
        bool copy_link_enabled = hit_test.context_is_link();
        this.pointer_url = copy_link_enabled ? hit_test.get_link_uri() : null;
        this.message_overlay_label.label = this.pointer_url ?? "";
        this.message_overlay_label.set_visible(copy_link_enabled);
        get_action(ACTION_COPY_LINK).set_enabled(copy_link_enabled);
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

    /** Shows and starts pulsing the progress meter. */
    private void on_background_work_timeout() {
        this.background_progress.fraction = 0.0;
        this.background_work_pulse.start();
        this.background_progress.show();
    }

    /////////////// Editing action callbacks /////////////////

    private void on_text_format(SimpleAction? action, Variant? new_state) {
        bool compose_as_html = new_state.get_string() == "html";
        action.set_state(new_state.get_string());

        foreach (string html_action in HTML_ACTIONS)
            get_action(html_action).set_enabled(compose_as_html);

        update_cursor_actions();

        var show_formatting = get_action(ACTION_SHOW_FORMATTING);
        show_formatting.set_enabled(compose_as_html);
        update_formatting_toolbar();

        this.body.set_rich_text(compose_as_html);

        this.config.compose_as_html = compose_as_html;
        this.more_options_button.popover.popdown();
    }

    private void on_show_formatting(GLib.SimpleAction? action,
                                    GLib.Variant? new_state) {
        bool show_formatting = new_state.get_boolean();
        this.config.formatting_toolbar_visible = show_formatting;
        action.set_state(new_state);

        update_formatting_toolbar();
        this.update_color_icon.begin(Util.Gtk.rgba(0, 0, 0, 0));
    }

    private void on_select_dictionary(SimpleAction action, Variant? param) {
        this.select_dictionary_button.toggled();
    }

    private void on_command_state_changed(bool can_undo, bool can_redo) {
        get_action(Action.Edit.UNDO).set_enabled(can_undo);
        get_action(Action.Edit.REDO).set_enabled(can_redo);
    }

    private void on_selection_changed() {
        update_cursor_actions();
    }

    private void on_undo() {
        this.body.undo();
    }

    private void on_redo() {
        this.body.redo();
    }

    private void on_cut() {
        this.body.cut_clipboard();
    }

    private void on_copy() {
        this.body.copy_clipboard();
    }

    private void on_copy_link(SimpleAction action, Variant? param) {
        Gtk.Clipboard c = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        // XXX could this also be the cursor URL? We should be getting
        // the target URLn as from the action param
        c.set_text(this.pointer_url, -1);
        c.store();
    }

    private void on_paste() {
        if (this.body.is_rich_text) {
            // Check for pasted image in clipboard
            Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
            bool has_image = clipboard.wait_is_image_available();
            if (has_image) {
                insert_image(true);
            } else {
                this.body.paste_rich_text();
            }
        } else {
            this.body.paste_plain_text();
        }
    }

    private void on_paste_without_formatting(SimpleAction action, Variant? param) {
        this.body.paste_plain_text();
    }

    private void on_select_all(SimpleAction action, Variant? param) {
        this.body.select_all();
    }

    private void on_indent() {
        this.body.indent_line();
    }

    private void on_olist() {
        this.body.insert_olist();
    }

    private void on_ulist() {
        this.body.insert_ulist();
    }

    private void on_justify(GLib.Action action, GLib.Variant? param) {
        this.body.execute_editing_command("justify" + param.get_string());
    }

    private void on_insert_image() {
        insert_image(false);
    }

    private void on_insert_link() {
        LinkPopover.Type type = LinkPopover.Type.NEW_LINK;
        string url = "https://";
        if (this.cursor_url != null) {
            type = LinkPopover.Type.EXISTING_LINK;
            url = this.cursor_url;
        }

        this.new_link_popover.begin(type, url, (obj, res) => {
                LinkPopover popover = this.new_link_popover.end(res);

                var style = this.insert_link_button.get_style_context();

                // We have to disconnect then reconnect the selection
                // changed signal for the duration of the popover
                // being active since if the user selects the text in
                // the URL entry, then the editor will lose its
                // selection, the inset link action will become
                // disabled, and the popover will disappear
                this.body.notify["has-selection"].disconnect(on_selection_changed);
                popover.closed.connect(() => {
                        this.body.notify["has-selection"].connect(on_selection_changed);
                        style.set_state(NORMAL);
                    });

                popover.set_relative_to(this.insert_link_button);
                popover.popup();
                style.set_state(ACTIVE);
            });
    }

    private void on_remove_format(SimpleAction action, Variant? param) {
        this.body.execute_editing_command("removeformat");
        this.body.execute_editing_command("removeparaformat");
        this.body.execute_editing_command("unlink");
        this.body.execute_editing_command_with_argument("backcolor", "#ffffff");
        this.body.execute_editing_command_with_argument("forecolor", "#000000");
    }

    private void on_font_family(GLib.SimpleAction action, GLib.Variant? param) {
        string font = param.get_string();
        this.body.execute_editing_command_with_argument(
            "fontname", font
        );
        action.set_state(font);

        this.font_button_stack.visible_child_name = font;
        this.font_button.popover.popdown();
    }

    private void on_font_size(GLib.SimpleAction action, GLib.Variant? param) {
        string size = "";
        if (param.get_string() == "small")
            size = "1";
        else if (param.get_string() == "medium")
            size = "3";
        else // Large
            size = "7";

        this.body.execute_editing_command_with_argument("fontsize", size);
        action.set_state(param.get_string());

        this.font_size_button.popover.popdown();
    }

    private void on_select_color() {
        var dialog = new Gtk.ColorChooserDialog(
            _("Select Color"),
            get_toplevel() as Gtk.Window
        );
        if (dialog.run() == Gtk.ResponseType.OK) {
            var rgba = dialog.get_rgba();
            this.body.execute_editing_command_with_argument(
                "forecolor", rgba.to_string()
            );

            this.update_color_icon.begin(rgba);
        }
        dialog.destroy();
    }

    private void on_action(GLib.SimpleAction action, GLib.Variant? param) {
        // Uses the unprefixed name as a command for the web view
        string[] prefixed_action_name = action.get_name().split(".");
        string action_name = prefixed_action_name[
            prefixed_action_name.length - 1
        ];
        this.body.execute_editing_command(action_name);
    }

    private void on_toggle_action(GLib.SimpleAction? action,
                                  GLib.Variant? param) {
        action.change_state(!action.state.get_boolean());
    }

    private void on_open_inspector() {
        this.body.get_inspector().show();
    }

}
