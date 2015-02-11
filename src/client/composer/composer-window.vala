/* Copyright 2011-2015 Yorba Foundation
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
            string new_title = Geary.String.is_empty_or_whitespace(composer.subject_entry.text)
                ? DEFAULT_TITLE : composer.subject_entry.text.strip();
            if (GearyApplication.instance.is_running_unity)
                title = new_title;
            else
                composer.header.title = new_title;
        });
        composer.subject_entry.changed();
        
        if (!GearyApplication.instance.is_running_unity) {
            composer.header.show_close_button = true;
            if (composer.header.parent != null)
                composer.header.parent.remove(composer.header);
            set_titlebar(composer.header);
        }
        
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
    
    public void remove_composer() {
        warning("Detached composer received remove");
    }
}

