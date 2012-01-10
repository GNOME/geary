/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// A single-child container that renders its a background color.
public class BackgroundBox : Gtk.Frame {
    public BackgroundBox() {
        Object(label: null);
        shadow_type = Gtk.ShadowType.NONE;
    }
    
    public override bool draw(Cairo.Context cr) {
        Gtk.StyleContext sc = get_style_context();
        
        sc.save();
        sc.set_state(get_state_flags());
        sc.render_background(cr, 0, 0, get_allocated_width(), get_allocated_height());
        sc.restore();
        
        base.draw(cr);
        return false;
    }
}

