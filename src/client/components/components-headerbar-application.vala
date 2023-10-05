/*
 * Copyright © 2017 Software Freedom Conservancy Inc.
 * Copyright © 2021 Michael Gratton <mike@vee.net>
 * Copyright © 2022 Cédric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * The Application HeaderBar
 *
 * @see Application.MainWindow
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-headerbar-application.ui")]
public class Components.ApplicationHeaderBar : Hdy.HeaderBar {

    [GtkChild] private unowned Gtk.MenuButton app_menu_button;
    [GtkChild] public unowned MonitoredSpinner spinner;


    construct {
        Gtk.Builder builder = new Gtk.Builder.from_resource("/org/gnome/Geary/components-menu-application.ui");
        MenuModel app_menu = (MenuModel) builder.get_object("app_menu");

        this.app_menu_button.popover = new Gtk.Popover.from_model(null, app_menu);
    }

    public void show_app_menu() {
        this.app_menu_button.clicked();
    }

}
