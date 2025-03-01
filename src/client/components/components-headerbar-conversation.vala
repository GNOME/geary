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
public class Components.ConversationHeaderBar : Adw.Bin {

    public bool find_open { get; set; default = false; }

    public bool compact { get; set; default = false; }

    [GtkChild] public unowned ConversationActions left_actions;
    [GtkChild] public unowned ConversationActions right_actions;

    [GtkChild] private unowned Gtk.ToggleButton find_button;

    [GtkChild] private unowned Adw.HeaderBar conversation_header;
    // Keep a strong ref when it's temporarily removed
    private Adw.HeaderBar? _conversation_header = null;

    //XXX GTK4 need to figure out close buttons
#if 0
    public bool show_close_button {
        get {
            return this.conversation_header.show_close_button;
        }
        set {
            this.conversation_header.show_close_button = value;
        }
    }
#endif

    construct {
        this.bind_property(
            "find-open",
            this.find_button, "active",
            SYNC_CREATE | BIDIRECTIONAL
        );
    }

    public override void dispose() {
        this._conversation_header = null;
        base.dispose();
    }

    public void set_conversation_header(Adw.HeaderBar header)
            requires (header.parent == null) {
        this._conversation_header = null;
        header.hexpand = true;
        //XXX GTK4 need to figure out close buttons
        // header.show_close_button = this.conversation_header.show_close_button;
        this.child = header;
    }

    public void remove_conversation_header(Adw.HeaderBar header) {
        //XXX GTK4 need to figure out close buttons
        // this.conversation_header.show_close_button = header.show_close_button;
        this.child = this.conversation_header;
    }

    public void set_find_sensitive(bool is_sensitive) {
        this.find_button.sensitive = is_sensitive;
    }
}
