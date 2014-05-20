/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ScrollableOverlay : Gtk.Overlay, Gtk.Scrollable {
    
    private Gtk.Scrollable main_child;
    
    public Gtk.Adjustment hadjustment { get; set; }
    
    public Gtk.Adjustment vadjustment { get; set; }
    
    public Gtk.ScrollablePolicy hscroll_policy { get; set; }
    
    public Gtk.ScrollablePolicy vscroll_policy { get; set; }
    
    public ScrollableOverlay(Gtk.Scrollable main_child) {
        this.main_child = main_child;
        add((Gtk.Widget) main_child);
        
        bind_property("hadjustment", main_child, "hadjustment",
            BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
        bind_property("vadjustment", main_child, "vadjustment",
            BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
        bind_property("hscroll_policy", main_child, "hscroll_policy",
            BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
        bind_property("vscroll_policy", main_child, "vscroll_policy",
            BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
        
        realize.connect(() => {
            vadjustment.value_changed.connect(on_scroll);
            hadjustment.value_changed.connect(on_scroll);
        });
        get_child_position.connect(on_child_position);
    }
    
    private bool on_child_position(Gtk.Widget widget, Gdk.Rectangle allocation) {
         return ((ComposerEmbed) widget).set_position(ref allocation, hadjustment.value, vadjustment.value);
    }
    
    private void on_scroll() {
        queue_resize();
    }
}

