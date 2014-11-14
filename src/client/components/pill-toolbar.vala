/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Interface for creating a Nautilus-style "pill" toolbar.  Use only as directed.
 *
 * Subclasses should inherit from some Gtk.Container and provide pack_start() and
 * pack_end() methods with the correct signature.  They also need to have action_group
 * and size properties and call initialize() in their constructors.
 */
public interface PillBar : Gtk.Container {
    protected abstract Gtk.ActionGroup action_group { get; set; }
    protected abstract Gtk.SizeGroup size { get; set; }
    
    public abstract void pack_start(Gtk.Widget widget);
    public abstract void pack_end(Gtk.Widget widget);
    
    protected virtual void initialize(Gtk.ActionGroup toolbar_action_group) {
        action_group = toolbar_action_group;
        size = new Gtk.SizeGroup(Gtk.SizeGroupMode.VERTICAL);
    }
    
    public virtual void add_start(Gtk.Widget widget) {
        pack_start(widget);
        size.add_widget(widget);
    }
    
    public virtual void add_end(Gtk.Widget widget) {
        pack_end(widget);
        size.add_widget(widget);
    }
    
    protected virtual void setup_button(Gtk.Button b, string? icon_name, string action_name,
        bool show_label = false) {
        b.related_action = action_group.get_action(action_name);
        b.tooltip_text = b.related_action.tooltip;
        b.related_action.notify["tooltip"].connect(() => { b.tooltip_text = b.related_action.tooltip; });
        
        // Load icon by name with this fallback order: specified icon name, the action's icon name,
        // the action's stock ID ... although stock IDs are being deprecated, that's how we specify
        // the icon in the GtkActionEntry (also being deprecated) and GTK+ 3.14 doesn't support that
        // any longer
        string? icon_to_load = icon_name ?? b.related_action.icon_name;
        if (icon_to_load == null)
            icon_to_load = b.related_action.stock_id;
        
        // set pixel size to force GTK+ to load our images from our installed directory, not the theme
        // directory
        if (icon_to_load != null) {
            Gtk.Image image = new Gtk.Image.from_icon_name(icon_to_load, Gtk.IconSize.MENU);
            image.set_pixel_size(16);
            b.image = image;
        }
        
        // Unity buttons are a bit tight
        if (GearyApplication.instance.is_running_unity && b.image != null)
            b.image.margin = b.image.margin + 4;
        
        b.always_show_image = true;
        
        if (!show_label)
            b.label = null;
    }
    
    /**
     * Given an icon and action, creates a button that triggers the action.
     */
    public virtual Gtk.Button create_toolbar_button(string? icon_name, string action_name, bool show_label = false) {
        Gtk.Button b = new Gtk.Button();
        setup_button(b, icon_name, action_name, show_label);
        
        return b;
    }
    
    /**
     * Given an icon and action, creates a toggle button that triggers the action.
     */
    public virtual Gtk.Button create_toggle_button(string? icon_name, string action_name) {
        Gtk.ToggleButton b = new Gtk.ToggleButton();
        setup_button(b, icon_name, action_name);
        
        return b;
    }
    
    /**
     * Given an icon, menu, and action, creates a button that triggers the menu and the action.
     */
    public virtual Gtk.MenuButton create_menu_button(string? icon_name, Gtk.Menu? menu, string action_name) {
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
    public virtual Gtk.Box create_pill_buttons(Gee.Collection<Gtk.Button> buttons,
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

/**
 * A pill-style header bar.
 */
public class PillHeaderbar : Gtk.HeaderBar, PillBar {
    protected Gtk.ActionGroup action_group { get; set; }
    protected Gtk.SizeGroup size { get; set; }
    
    public PillHeaderbar(Gtk.ActionGroup toolbar_action_group) {
        initialize(toolbar_action_group);
    }
}

/**
 * A pill-style toolbar.
 */
public class PillToolbar : Gtk.Box, PillBar {
    protected Gtk.ActionGroup action_group { get; set; }
    protected Gtk.SizeGroup size { get; set; }
    
    public PillToolbar(Gtk.ActionGroup toolbar_action_group) {
        Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 6);
        initialize(toolbar_action_group);
    }
    
    public new void pack_start(Gtk.Widget widget) {
        base.pack_start(widget, false, false, 0);
    }
    
    public new void pack_end(Gtk.Widget widget) {
        base.pack_end(widget, false, false, 0);
    }
}

