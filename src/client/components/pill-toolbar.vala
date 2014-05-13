/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Class for creating a Nautilus-style "pill" toolbar.  Use only as directed.
 */
public class PillToolbar : Gtk.HeaderBar {
    private Gtk.ActionGroup action_group;
    private Gtk.SizeGroup size = new Gtk.SizeGroup(Gtk.SizeGroupMode.VERTICAL);
    
    public PillToolbar(Gtk.ActionGroup toolbar_action_group) {
        action_group = toolbar_action_group;
    }
    
    public void add_start(Gtk.Widget *widget) {
        pack_start(widget);
        size.add_widget(widget);
    }
    
    public void add_end(Gtk.Widget *widget) {
        pack_end(widget);
        size.add_widget(widget);
    }
    
    protected void setup_button(Gtk.Button b, string? icon_name, string action_name,
        bool show_label = false) {
        b.related_action = action_group.get_action(action_name);
        b.tooltip_text = b.related_action.tooltip;
        b.related_action.notify["tooltip"].connect(() => { b.tooltip_text = b.related_action.tooltip; });
        b.image = new Gtk.Image.from_icon_name(icon_name != null ? icon_name :
            b.related_action.icon_name, Gtk.IconSize.MENU);
        // Unity buttons are a bit tight
#if ENABLE_UNITY
        b.image.margin = b.image.margin + 4;
#endif
        b.always_show_image = true;
        
        if (!show_label)
            b.label = null;
    }
    
    /**
     * Given an icon and action, creates a button that triggers the action.
     */
    public Gtk.Button create_toolbar_button(string? icon_name, string action_name, bool show_label = false) {
        Gtk.Button b = new Gtk.Button();
        setup_button(b, icon_name, action_name, show_label);
        
        return b;
    }
    
    /**
     * Given an icon and action, creates a toggle button that triggers the action.
     */
    public Gtk.Button create_toggle_button(string? icon_name, string action_name) {
        Gtk.ToggleButton b = new Gtk.ToggleButton();
        setup_button(b, icon_name, action_name);
        
        return b;
    }
    
    /**
     * Given an icon, menu, and action, creates a button that triggers the menu and the action.
     */
    public Gtk.MenuButton create_menu_button(string? icon_name, Gtk.Menu? menu, string action_name) {
        Gtk.MenuButton b = new Gtk.MenuButton();
        setup_button(b, icon_name, action_name);
        b.popup = menu;
        
        return b;
    }
    
    /**
     * Given a list of buttons, creates a "pill-style" tool item that can be appended to this
     * toolbar.  Optionally adds spacers "before" and "after" the buttons (those terms depending
     * on Gtk.TextDirection)
     */
    public Gtk.Box create_pill_buttons(Gee.Collection<Gtk.Button> buttons,
        bool before_spacer = true, bool after_spacer = false) {
        Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        box.valign = Gtk.Align.CENTER;
        box.halign = Gtk.Align.CENTER;
        
        if (buttons.size > 1) {
            box.get_style_context().add_class(Gtk.STYLE_CLASS_RAISED);
            box.get_style_context().add_class(Gtk.STYLE_CLASS_LINKED);
        }
        
        foreach(Gtk.Button button in buttons)
            box.add(button);
                
        return box;
    }
}

