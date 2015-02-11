/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ComposerBox : Gtk.Frame, ComposerContainer {
    
    private ComposerWidget composer;
    private Gee.Set<Geary.App.Conversation>? prev_selection = null;
    private bool has_accel_group = false;
    private Binding? title_binding = null;
    
    public Gtk.Window top_window {
        get { return (Gtk.Window) get_toplevel(); }
    }
    
    public ComposerBox(ComposerWidget composer) {
        this.composer = composer;
        
        add(composer);
        composer.editor.focus_in_event.connect(on_focus_in);
        composer.editor.focus_out_event.connect(on_focus_out);
        show();
        
        if (composer.state == ComposerWidget.ComposerState.NEW) {
            ConversationListView conversation_list_view = ((MainWindow) GearyApplication.
                instance.controller.main_window).conversation_list_view;
            prev_selection = conversation_list_view.get_selected_conversations();
            conversation_list_view.get_selection().unselect_all();
            
            title_binding = composer.bind_property("window-title", composer.header, "title",
                BindingFlags.SYNC_CREATE);
            composer.header.parent.remove(composer.header);
            GearyApplication.instance.controller.main_window.main_toolbar.set_conversation_header(
                composer.header);
            get_style_context().add_class("full-pane");
        }
    }
    
    public void remove_composer() {
        if (composer.editor.has_focus)
            on_focus_out();
        composer.editor.focus_in_event.disconnect(on_focus_in);
        composer.editor.focus_out_event.disconnect(on_focus_out);
        
        remove(composer);
        close_container();
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
        if (get_style_context().has_class("full-pane"))
            GearyApplication.instance.controller.main_window.main_toolbar.remove_conversation_header(
                composer.header);
        if (title_binding != null)
            title_binding.unbind();
        
        composer.state = ComposerWidget.ComposerState.DETACHED;
        composer.editor.focus_in_event.disconnect(on_focus_in);
        composer.editor.focus_out_event.disconnect(on_focus_out);
        
        if (prev_selection != null) {
            ConversationListView conversation_list_view = ((MainWindow) GearyApplication.
                instance.controller.main_window).conversation_list_view;
            if (prev_selection.is_empty)
                // Need to trigger "No messages selected"
                conversation_list_view.conversations_selected(prev_selection);
            else
                conversation_list_view.select_conversations(prev_selection);
            prev_selection = null;
        }
    }
    
    public void close_container() {
        if (visible)
            vanish();
        parent.remove(this);
    }
}

