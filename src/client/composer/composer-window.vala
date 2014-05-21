/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Window for sending messages.
public class ComposerWindow : Gtk.Window, ComposerContainer {

    private const string DEFAULT_TITLE = _("New Message");
    
    private bool closing = false;
    
    public ComposerWindow(ComposerWidget composer) {
        Object(type: Gtk.WindowType.TOPLEVEL);
        
        add(composer);
        composer.subject_entry.changed.connect(() => {
            title = Geary.String.is_empty(composer.subject_entry.text.strip()) ? DEFAULT_TITLE :
                composer.subject_entry.text.strip();
        });
        composer.subject_entry.changed();
        
        add_accel_group(composer.ui.get_accel_group());
        show();
        set_position(Gtk.WindowPosition.CENTER);
    }
    
    public Gtk.Window top_window {
        get { return this; }
    }
    
    public override void show() {
        set_default_size(680, 600);
        base.show();
    }
    
    public void close_container() {
        closing = true;
        destroy();
    }
    
    public override bool delete_event(Gdk.EventAny event) {
        return !(closing ||
            ((ComposerWidget) get_child()).should_close() == ComposerWidget.CloseStatus.DO_CLOSE);
    }
    
    public void vanish() {
        hide();
    }
}

