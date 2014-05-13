/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ComposerEmbed : Gtk.Box, ComposerContainer {
    
    private static string embed_id = "composer_embed";
    
    private ComposerWidget? composer = null;
    private ConversationViewer conversation_viewer;
    private Gee.Set<Geary.App.Conversation>? prev_selection = null;
    
    public Gtk.Window top_window {
        get { return (Gtk.Window) get_toplevel(); }
    }
    public bool is_active {
        get { return composer != null; }
    }
    
    public ComposerEmbed(ConversationViewer conversation_viewer) {
        Object(orientation: Gtk.Orientation.VERTICAL);
        this.conversation_viewer = conversation_viewer;
        no_show_all = true;
        halign = Gtk.Align.FILL;
        valign = Gtk.Align.FILL;
        
        Gtk.Toolbar toolbar = new Gtk.Toolbar();
        toolbar.set_icon_size(Gtk.IconSize.MENU);
        Gtk.ToolButton close = new Gtk.ToolButton.from_stock("gtk-close");
        Gtk.ToolButton detach = new Gtk.ToolButton.from_stock("gtk-goto-top");
        Gtk.SeparatorToolItem filler = new Gtk.SeparatorToolItem();
        filler.set_expand(true);
        filler.set_draw(false);
        toolbar.insert(filler, -1);
        toolbar.insert(detach, -1);
        toolbar.insert(close, -1);
        pack_start(toolbar, false, false);
        toolbar.show_all();
        
        close.clicked.connect(on_close);
        detach.clicked.connect(on_detach);
    }
    
    public void new_composer(ComposerWidget new_composer, Geary.Email? referred) {
        if (!abandon_existing_composition(new_composer))
            return;
        
        WebKit.DOM.HTMLElement? email_element = null;
        if (referred != null)
            email_element = conversation_viewer.web_view.get_dom_document().get_element_by_id(
                conversation_viewer.get_div_id(referred.id)) as WebKit.DOM.HTMLElement;
        if (email_element == null) {
            ConversationListView conversation_list_view = ((MainWindow) GearyApplication.
                instance.controller.main_window).conversation_list_view;
            prev_selection = conversation_list_view.get_selected_conversations();
            conversation_list_view.get_selection().unselect_all();
            email_element = conversation_viewer.web_view.get_dom_document().get_element_by_id(
                "placeholder") as WebKit.DOM.HTMLElement;
        }
        
        try {
            conversation_viewer.show_conversation_div();
            email_element.insert_adjacent_html("afterend",
                @"<div id='$embed_id'></div>");
        } catch (Error error) {
            debug("Error creating embed element: %s", error.message);
            return;
        }
        pack_start(new_composer, true, true);
        new_composer.editor.focus_in_event.connect(on_focus_in);
        new_composer.editor.focus_out_event.connect(on_focus_out);
        new_composer.show_all();
        show();
        present();
        this.composer = new_composer;
    }
    
    public bool abandon_existing_composition(ComposerWidget? new_composer = null) {
        if (composer == null)
            return true;
        
        present();
        AlertDialog dialog;
        if (new_composer != null)
            dialog = new AlertDialog(top_window, Gtk.MessageType.QUESTION,
                _("Do you want to discard the existing composition?"), null, Gtk.Stock.DISCARD,
                Gtk.Stock.CANCEL, _("Open New Composition Window"), Gtk.ResponseType.YES);
        else
            dialog = new AlertDialog(top_window, Gtk.MessageType.QUESTION,
                _("Do you want to discard the existing composition?"), null, Gtk.Stock.DISCARD,
                Gtk.Stock.CANCEL, _("Move Composition to New Window"), Gtk.ResponseType.YES);
        Gtk.ResponseType response = dialog.run();
        if (response == Gtk.ResponseType.OK) {
            close();
            return true;
        }
        if (new_composer != null) {
            if (response == Gtk.ResponseType.YES)
                new ComposerWindow(new_composer);
            else
                new_composer.destroy();
        } else if (response == Gtk.ResponseType.YES) {
            on_detach();
            return true;
        }
        return false;
    }
    
    private void on_close() {
        if (composer.should_close() == ComposerWidget.CloseStatus.DO_CLOSE)
            close();
    }
    
    private void on_detach() {
        if (composer.editor.has_focus)
            on_focus_out();
        composer.editor.focus_in_event.disconnect(on_focus_in);
        composer.editor.focus_out_event.disconnect(on_focus_out);
        Gtk.Widget focus = top_window.get_focus();
        
        remove(composer);
        ComposerWindow window = new ComposerWindow(composer);
        ComposerWindow focus_win = focus.get_toplevel() as ComposerWindow;
        if (focus_win != null && focus_win == window)
            focus.grab_focus();
        composer = null;
        close();
    }
    
    public bool set_position(Gtk.Widget widget, Gdk.Rectangle allocation) {
        WebKit.DOM.Element embed = conversation_viewer.web_view.get_dom_document().get_element_by_id(embed_id);
        if (embed == null)
            return false;
        
        allocation.x = (int) embed.offset_left;
        allocation.y = (int) embed.offset_top;
        allocation.width = (int) embed.offset_width;
        allocation.height = (int) embed.offset_height;
        return true;
    }
    
    private bool on_focus_in() {
        top_window.add_accel_group(composer.ui.get_accel_group());
        return false;
    }
    
    private bool on_focus_out() {
        top_window.remove_accel_group(composer.ui.get_accel_group());
        return false;
    }
    
    public void present() {
        conversation_viewer.web_view.get_dom_document().get_element_by_id(embed_id).scroll_into_view(true);
    }
    
    public unowned Gtk.Widget get_focus() {
        return top_window.get_focus();
    }
    
    private void close() {
        hide();
        if (composer != null) {
            composer.editor.focus_in_event.disconnect(on_focus_in);
            composer.editor.focus_out_event.disconnect(on_focus_out);
            remove(composer);
            composer.destroy();
            composer = null;
        }
        
        WebKit.DOM.Element embed = conversation_viewer.web_view.get_dom_document().get_element_by_id(embed_id);
        try{
            embed.parent_element.remove_child(embed);
        } catch (Error error) {
            warning("Could not remove embed from WebView: %s", error.message);
        }
        
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
}

