/*
 * Copyright © 2017 Software Freedom Conservancy Inc.
 * Copyright © 2021 Michael Gratton <mike@vee.net>
 * Copyright © 2022 Cédric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * The conversations headerbar.
 *
 * @see Application.MainWindow
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-headerbar-conversation.ui")]
public class Components.ConversationHeaderBar : Gtk.Bin {

    public bool find_open { get; set; default = false; }

    public ConversationActions shown_actions {
        get {
            return (ConversationActions) this.actions_squeezer.visible_child;
        }
    }

    [GtkChild] private unowned Hdy.Squeezer actions_squeezer;
    [GtkChild] public unowned ConversationActions full_actions;
    [GtkChild] public unowned ConversationActions compact_actions;

    [GtkChild] private unowned Gtk.ToggleButton find_button;
    [GtkChild] public unowned Gtk.Button back_button;

    [GtkChild] private unowned Hdy.HeaderBar conversation_header;

    public bool show_close_button {
        get {
            return this.conversation_header.show_close_button;
        }
        set {
            this.conversation_header.show_close_button = value;
        }
    }

    construct {
        this.actions_squeezer.notify["visible-child"].connect_after(
            () => { notify_property("shown-actions"); }
        );

        this.bind_property(
            "find-open",
            this.find_button, "active",
            SYNC_CREATE | BIDIRECTIONAL
        );
    }

    public void set_conversation_header(Hdy.HeaderBar header) {
        remove(this.conversation_header);
        header.hexpand = true;
        header.show_close_button = this.conversation_header.show_close_button;
        add(header);
    }

    public void remove_conversation_header(Hdy.HeaderBar header) {
        remove(header);
        this.conversation_header.show_close_button = header.show_close_button;
        add(this.conversation_header);
    }

    public void set_find_sensitive(bool is_sensitive) {
        this.find_button.sensitive = is_sensitive;
    }
}
