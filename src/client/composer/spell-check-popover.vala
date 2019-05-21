/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class SpellCheckPopover {

    /**
     * This signal is emitted then the selection of rows changes.
     *
     * @param active_langs The new set of active dictionaries after the
     *                     selection has changed.
     */
    public signal void selection_changed(string[] active_langs);

    private Gtk.Popover? popover = null;
    private GLib.GenericSet<string> selected_rows;
    private bool is_expanded = false;
    private Gtk.ListBox langs_list;
    private Gtk.SearchEntry search_box;
    private Gtk.ScrolledWindow view;
    private Gtk.Box content;
    private Configuration config;

    private enum SpellCheckStatus {
        INACTIVE,
        ACTIVE
    }

    private class SpellCheckLangRow : Gtk.ListBoxRow {

        /**
         * This signal is emitted then the user activates the row.
         *
         * @param lang_code The language code associated to this row (such as en_US).
         * @param status true if the associated dictionary should be enabled, false if it should be
         *               disabled.
         */
        public signal void toggled (string lang_code, bool status);

        /**
         * @brief Signal when the visibility has changed.
         */
        public signal void visibility_changed ();

        private string lang_code;
        private string lang_name;
        private string country_name;
        private bool is_lang_visible;
        private Gtk.Image active_image;
        private Gtk.Button remove_button;
        private SpellCheckStatus lang_active = SpellCheckStatus.INACTIVE;
        private Configuration config;

        public SpellCheckLangRow (string lang_code, Configuration config) {
            this.lang_code = lang_code;
            this.config = config;

            Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);

            lang_name = Util.International.language_name_from_locale(lang_code);
            country_name = Util.International.country_name_from_locale(lang_code);

            string label_text = lang_name;
            if (country_name != null)
                label_text += " (" + country_name + ")";
            Gtk.Label label = new Gtk.Label(label_text);
            label.set_halign(Gtk.Align.START);
            label.set_size_request(-1, 24);

            box.pack_start(label, false, false);

            Gtk.IconSize sz = Gtk.IconSize.SMALL_TOOLBAR;
            active_image = new Gtk.Image.from_icon_name("object-select-symbolic", sz);
            remove_button = new Gtk.Button();
            remove_button.set_relief(Gtk.ReliefStyle.NONE);
            box.pack_start(active_image, false, false, 6);
            box.pack_start(remove_button, true, true);
            remove_button.halign = Gtk.Align.END; // Make the button stay at the right end of the screen

            remove_button.clicked.connect(on_remove_clicked);

            is_lang_visible = false;
            foreach (string visible_lang in this.config.spell_check_visible_languages) {
                if (visible_lang == lang_code)
                    is_lang_visible = true;
            }

            foreach (string active_lang in this.config.spell_check_languages) {
                if (active_lang == lang_code)
                    lang_active = SpellCheckStatus.ACTIVE;
            }

            update_images();
            add(box);
        }

        public bool is_lang_active() {
            return lang_active == SpellCheckStatus.ACTIVE;
        }

        private void update_images() {
            Gtk.IconSize sz = Gtk.IconSize.SMALL_TOOLBAR;

            switch (lang_active) {
            case SpellCheckStatus.ACTIVE:
                active_image.set_from_icon_name("object-select-symbolic", sz);
                break;
            case SpellCheckStatus.INACTIVE:
                active_image.clear();
                break;
            }

            if (is_lang_visible) {
                remove_button.set_image(new Gtk.Image.from_icon_name("list-remove-symbolic", sz));
                remove_button.set_tooltip_text(_("Remove this language from the preferred list"));
            }
            else {
                remove_button.set_image(new Gtk.Image.from_icon_name("list-add-symbolic", sz));
                remove_button.set_tooltip_text(_("Add this language to the preferred list"));
            }
        }

        private void on_remove_clicked() {
            is_lang_visible = ! is_lang_visible;

            update_images();

            if (!is_lang_visible && lang_active == SpellCheckStatus.ACTIVE)
                set_lang_active(SpellCheckStatus.INACTIVE);

            if (is_lang_visible) {
                string[] visible_langs = this.config.spell_check_visible_languages;
                visible_langs += lang_code;
                this.config.spell_check_visible_languages = visible_langs;
            }
            else {
                string[] visible_langs = {};
                foreach (string lang in this.config.spell_check_visible_languages) {
                    if (lang != lang_code)
                        visible_langs += lang;
                }
                this.config.spell_check_visible_languages = visible_langs;
            }

            visibility_changed();
        }

        public bool match_filter(string filter) {
            string filter_down = filter.down();
            return ((lang_name != null ? filter_down in lang_name.down() : false) ||
                    (country_name != null ? filter_down in country_name.down() : false));
        }

        private void set_lang_active(SpellCheckStatus active) {
            lang_active = active;

            switch (active) {
                case SpellCheckStatus.ACTIVE:
                    // If the lang is not visible make it visible now
                    if (!is_lang_visible) {
                        string[] visible_langs = this.config.spell_check_visible_languages;
                        visible_langs += lang_code;
                        this.config.spell_check_visible_languages = visible_langs;
                        is_lang_visible = true;
                    }
                    break;
                case SpellCheckStatus.INACTIVE:
                    break;
            }

            update_images();
            this.toggled(lang_code, active == SpellCheckStatus.ACTIVE);
        }

        public void handle_activation(SpellCheckPopover spell_check_popover) {
            // Make sure that we do not enable the language when the user is just
            // trying to remove it from the list.
            if (!visible)
                return;

            switch (lang_active) {
                case SpellCheckStatus.ACTIVE:
                    set_lang_active(SpellCheckStatus.INACTIVE);
                    break;
                case SpellCheckStatus.INACTIVE:
                    set_lang_active(SpellCheckStatus.ACTIVE);
                    break;
            }
        }

        public bool is_row_visible(bool is_expanded) {
            return is_lang_visible || is_expanded;
        }
    }

    public SpellCheckPopover(Gtk.Widget button, Configuration config) {
        this.popover = new Gtk.Popover(button);
        this.config = config;
        this.selected_rows = new GLib.GenericSet<string>(GLib.str_hash, GLib.str_equal);
        setup_popover();
    }

    private bool filter_function (Gtk.ListBoxRow row) {
        string text = search_box.get_text();
        SpellCheckLangRow r = row as SpellCheckLangRow;
        return (r.is_row_visible(is_expanded) && r.match_filter(text));
    }

    private void setup_popover() {
        // We populate the popover with the list of languages that the user wants to see
        string[] languages = Util.International.get_available_dictionaries();

        content = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        search_box = new Gtk.SearchEntry();
        search_box.set_placeholder_text(_("Search for more languages"));
        search_box.changed.connect(on_search_box_changed);
        search_box.grab_focus.connect(on_search_box_grab_focus);
        content.pack_start(search_box, false, true);

        view = new Gtk.ScrolledWindow(null, null);
        view.set_shadow_type(Gtk.ShadowType.IN);
        view.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);

        langs_list = new Gtk.ListBox();
        langs_list.set_selection_mode(Gtk.SelectionMode.NONE);
        foreach (string lang in languages) {
            SpellCheckLangRow row = new SpellCheckLangRow(lang, this.config);
            langs_list.add(row);

            if (row.is_lang_active())
                selected_rows.add(lang);

            row.toggled.connect(this.on_row_toggled);
            row.visibility_changed.connect(this.on_visibility_changed);
        }
        langs_list.row_activated.connect(on_row_activated);
        view.add(langs_list);

        content.pack_start(view, true, true);

        langs_list.set_filter_func(this.filter_function);

        view.set_size_request(350, 300);
        popover.add(content);

        // Make sure that the search box does not get the focus first. We want it to have it only
        // if the user wants to perform an extended search.
        content.set_focus_child(view);
        content.set_margin_start(6);
        content.set_margin_end(6);
        content.set_margin_top(6);
        content.set_margin_bottom(6);
    }

    private void on_row_activated(Gtk.ListBoxRow row) {
        SpellCheckLangRow r = row as SpellCheckLangRow;
        r.handle_activation(this);
        // Make sure that we update the visible languages based on the
        // possibly updated is_lang_visible_properties.
        langs_list.invalidate_filter();
    }

    private void on_search_box_changed() {
        langs_list.invalidate_filter();
    }

    private void on_search_box_grab_focus() {
        set_expanded(true);
    }

    private void set_expanded(bool expanded) {
        is_expanded = expanded;
        langs_list.invalidate_filter();
    }

    /*
     * Toggle the visibility of the popover, and return the final status.
     *
     * @return true if the Popover is visible after the call, false otherwise.
     */
    public bool toggle() {
        if (popover.get_visible()) {
            popover.hide();
        }
        else {
            // Make sure that when the box is shown the list is not expanded anymore.
            search_box.set_text("");
            content.set_focus_child(view);
            is_expanded = false;
            langs_list.invalidate_filter();

            popover.show_all();
        }

        return popover.get_visible();
    }

    private void on_row_toggled(string lang_code, bool active) {
        if (active)
            selected_rows.add(lang_code);
        else
            selected_rows.remove(lang_code);

        // Signal that the selection has changed
        string[] active_langs = {};
        selected_rows.foreach((lang) => active_langs += lang);
        this.selection_changed(active_langs);
    }

    private void on_visibility_changed() {
        langs_list.invalidate_filter();
    }

}
