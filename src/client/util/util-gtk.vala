/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace GtkUtil {

// The reason GtkUtil.ToggleToolbarDropdown exists (rather than using Gtk.MenuToolButton) is that
// the latter creates two separate buttons, one for the icon (which activates the "default" action)
// and one for the arrow (which presents the dropdown menu).  We need a single button that shows
// the dropdown menu only, hence this version.
//
// In order to use this, create a Gtk.ToggleToolButton and call attach().
//
// TODO: An better solution would be for this to subclass Gtk.ToggleToolButton and register class
// with Gtk.Builder and Glade.
//
// TODO: Would be better to get the icon from the ToggleToolbarButton (could do this even without
// above improvement), but unlike the label, that's not so straightforward due to the number of
// ways of representing an icon in GTK.

public class ToggleToolbarDropdown : Geary.BaseObject {
    public const int DEFAULT_PADDING = 2;
    
    public bool show_arrow { get; set; default = true; }
    public Gtk.Menu menu { get; private set; }
    public Gtk.Menu proxy_menu { get; private set; }
    
    private int padding;
    private Gtk.Image icon;
    private Gtk.Label label = new Gtk.Label(null);
    private Gtk.Arrow icon_arrow = new Gtk.Arrow(Gtk.ArrowType.DOWN, Gtk.ShadowType.NONE);
    private Gtk.Box icon_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
    private Gtk.Arrow label_arrow = new Gtk.Arrow(Gtk.ArrowType.DOWN, Gtk.ShadowType.NONE);
    private Gtk.Box label_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
    private Gtk.ToggleToolButton? owner = null;
    
    public ToggleToolbarDropdown(Icon icon, Gtk.IconSize icon_size, Gtk.Menu? supplied_menu,
        Gtk.Menu? supplied_proxy_menu, int padding = DEFAULT_PADDING) {
        this.padding = padding;
        this.icon = new Gtk.Image.from_gicon(icon, icon_size);
        menu = supplied_menu ?? new Gtk.Menu();
        proxy_menu = supplied_proxy_menu ?? new Gtk.Menu();
        
        // icon widget
        icon_box.pack_start(this.icon, true, true, padding);
        icon_box.pack_end(icon_arrow, true, true, padding);
        icon_box.no_show_all = true;
        
        // label widget
        label_box.pack_start(this.label, true, true, padding);
        label_box.pack_end(label_arrow, true, true, padding);
        label_box.no_show_all = true;
        
        this.icon.visible = true;
        this.icon_arrow.visible = show_arrow;
        icon_box.visible = true;
        
        this.label.visible = true;
        this.label_arrow.visible = show_arrow;
        label_box.visible = true;
        
        notify["show-arrow"].connect(on_refresh_now);
    }
    
    ~ToggleToolbarDropdown() {
        detach();
    }
    
    public void attach(Gtk.ToggleToolButton owner) {
        if (this.owner != null) {
            debug("ToggleToolbarDropdown already attached");
            
            return;
        }
        
        this.owner = owner;
        
        owner.set_icon_widget(icon_box);
        owner.set_label_widget(label_box);
        
        menu.attach_to_widget(owner, null);
        menu.deactivate.connect(on_menu_deactivated);
        
        add_proxy_menu(owner, owner.label, proxy_menu);
        
        owner.clicked.connect(on_clicked);
        owner.notify["label"].connect(on_refresh_now);
        owner.notify["active"].connect(on_refresh_now);
        owner.notify["is-important"].connect(on_refresh_now);
        owner.notify["sensitive"].connect(on_refresh_now);
        owner.toolbar_reconfigured.connect(on_refresh_now);
        
        on_refresh_now();
    }
    
    public void detach() {
        if (owner == null)
            return;
        
        owner.clicked.disconnect(on_clicked);
        owner.notify["label"].disconnect(on_refresh_now);
        owner.notify["active"].disconnect(on_refresh_now);
        owner.notify["is-important"].disconnect(on_refresh_now);
        owner.notify["sensitive"].disconnect(on_refresh_now);
        owner.toolbar_reconfigured.disconnect(on_refresh_now);
        
        this.owner = null;
    }
    
    private void on_menu_deactivated() {
        if (owner != null)
            owner.active = false;
    }
    
    private void on_clicked() {
        if (owner != null && owner.active)
            menu.popup(null, null, menu_popup_relative, 0, 0);
    }
    
    private void on_refresh_now() {
        if (owner == null)
            return;
        
        label.set_label(owner.label);
        
        icon.sensitive = owner.sensitive;
        icon_arrow.sensitive = owner.sensitive;
        label.sensitive = owner.sensitive;
        label_arrow.sensitive = owner.sensitive;
        
        switch (owner.get_toolbar_style()) {
            case Gtk.ToolbarStyle.BOTH:
                icon.visible = true;
                icon_arrow.visible = show_arrow;
                label.visible = true;
                label_arrow.visible = false;
            break;
            
            case Gtk.ToolbarStyle.ICONS:
                icon.visible = true;
                icon_arrow.visible = show_arrow;
                label.visible = false;
                label.visible = false;
            break;
            
            case Gtk.ToolbarStyle.TEXT:
                icon.visible = false;
                icon_arrow.visible = false;
                label.visible = true;
                label_arrow.visible = show_arrow;
            break;
            
            case Gtk.ToolbarStyle.BOTH_HORIZ:
            default:
                icon.visible = true;
                icon_arrow.visible = !owner.is_important && show_arrow;
                label.visible = owner.is_important;
                label_arrow.visible = owner.is_important && show_arrow;
            break;
        }
    }
}

// Use this MenuPositionFunc to position a popup menu relative to a widget
// with Gtk.Menu.popup().
//
// You *must* attach the button widget with Gtk.Menu.attach_to_widget() before
// this function can be used.
public void menu_popup_relative(Gtk.Menu menu, out int x, out int y, out bool push_in) {
    menu.realize();
    
    int rx, ry;
    menu.get_attach_widget().get_window().get_origin(out rx, out ry);
    
    Gtk.Allocation menu_button_allocation;
    menu.get_attach_widget().get_allocation(out menu_button_allocation);
    
    x = rx + menu_button_allocation.x;
    y = ry + menu_button_allocation.y + menu_button_allocation.height;
    
    push_in = false;
}

public void add_proxy_menu(Gtk.ToolItem tool_item, string label, Gtk.Menu proxy_menu) {
    Gtk.MenuItem proxy_menu_item = new Gtk.MenuItem.with_label(label);
    proxy_menu_item.submenu = proxy_menu;
    tool_item.create_menu_proxy.connect((sender) => {
        sender.set_proxy_menu_item("proxy", proxy_menu_item);
        return true;
    });
}

public void add_accelerator(Gtk.UIManager ui_manager, Gtk.ActionGroup action_group,
    string accelerator, string action) {
    // Parse the accelerator.
    uint key = 0;
    Gdk.ModifierType modifiers = 0;
    Gtk.accelerator_parse(accelerator, out key, out modifiers);
    if (key == 0) {
        debug("Failed to parse accelerator '%s'", accelerator);
        return;
    }
    
    // Connect the accelerator to the action.
    ui_manager.get_accel_group().connect(key, modifiers, Gtk.AccelFlags.VISIBLE,
        (group, obj, key, modifiers) => {
            action_group.get_action(action).activate();
            return false;
        });
}

}

