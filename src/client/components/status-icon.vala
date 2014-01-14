/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class StatusIcon : Gtk.StatusIcon {
    private Gtk.Menu context_menu;
    
    public StatusIcon() {
        set_from_icon_name("geary");
        
        // Setup the context menu.
        GearyApplication.instance.load_ui_file("status_icon_menu.ui");
        context_menu = (Gtk.Menu) GearyApplication.instance.ui_manager.get_widget("/ui/StatusIconMenu");
        context_menu.foreach(GtkUtil.show_menuitem_accel_labels);
        context_menu.show_all();
        
        activate.connect(on_activate);
        popup_menu.connect(on_popup_menu);
    }
    
    private void on_activate() {
        if (GearyApplication.instance.controller.main_window.is_active) {
            GearyApplication.instance.controller.main_window.hide();
        } else {
            GearyApplication.instance.controller.main_window.show();
            GearyApplication.instance.controller.main_window.present();
        }
    }
    
    private void on_popup_menu(uint button, uint activate_time) {
        context_menu.popup(null, null, position_menu, button, activate_time);
    }
}
