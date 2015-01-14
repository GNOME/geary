/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ComposerBox : Gtk.EventBox, ComposerContainer {
    
    private ComposerWidget composer;
    private bool has_accel_group = false;
    
    public Gtk.Window top_window {
        get { return (Gtk.Window) get_toplevel(); }
    }
    
    public ComposerBox(ComposerWidget composer) {
        this.composer = composer;
        
        add(composer);
        composer.editor.focus_in_event.connect(on_focus_in);
        composer.editor.focus_out_event.connect(on_focus_out);
        show();
    }
    
    public Gtk.Widget? remove_composer() {
        if (composer.editor.has_focus)
            on_focus_out();
        composer.editor.focus_in_event.disconnect(on_focus_in);
        composer.editor.focus_out_event.disconnect(on_focus_out);
        Gtk.Widget? focus = top_window.get_focus();
        
        remove(composer);
        close_container();
        return focus;
    }
    
    
    private bool on_focus_in() {
        // For some reason, on_focus_in gets called a bunch upon construction.
        if (!has_accel_group)
            top_window.add_accel_group(composer.ui.get_accel_group());
        has_accel_group = true;
        return false;
    }
    
    private bool on_focus_out() {
        top_window.remove_accel_group(composer.ui.get_accel_group());
        has_accel_group = false;
        return false;
    }
    
    public void present() {
        top_window.present();
    }
    
    public unowned Gtk.Widget get_focus() {
        return top_window.get_focus();
    }
    
    public void vanish() {
        hide();
        parent.hide();
        composer.state = ComposerWidget.ComposerState.DETACHED;
        composer.editor.focus_in_event.disconnect(on_focus_in);
        composer.editor.focus_out_event.disconnect(on_focus_out);
    }
    
    public void close_container() {
        if (visible)
            vanish();
        parent.remove(this);
    }
}

