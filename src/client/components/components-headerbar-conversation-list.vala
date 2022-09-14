/*
 * Copyright © 2017 Software Freedom Conservancy Inc.
 * Copyright © 2021 Michael Gratton <mike@vee.net>
 * Copyright © 2022 Cédric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * The conversation list headerbar.
 *
 * @see Application.MainWindow
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-headerbar-conversation-list.ui")]
public class Components.ConversationListHeaderBar : Hdy.HeaderBar {

    public string account { get; set; }
    public string folder { get; set; }
    public bool search_open { get; set; default = false; }
    public bool selection_open { get; set; default = false; }

    [GtkChild] private unowned Gtk.ToggleButton search_button;
    [GtkChild] private unowned Gtk.ToggleButton selection_button;
    [GtkChild] public unowned Gtk.Button back_button;


    construct {
        this.bind_property("account", this, "title", BindingFlags.SYNC_CREATE);
        this.bind_property("folder", this, "subtitle", BindingFlags.SYNC_CREATE);

        this.bind_property(
            "search-open",
            this.search_button, "active",
            SYNC_CREATE | BIDIRECTIONAL
        );
        this.bind_property(
            "selection-open",
            this.selection_button, "active",
            SYNC_CREATE | BIDIRECTIONAL
        );
    }
}
