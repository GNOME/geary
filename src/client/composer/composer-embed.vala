/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ComposerEmbed : Gtk.Box, ComposerContainer {
    
    private static string embed_id = "composer_embed";
    
    private ComposerWidget composer;
    private ConversationViewer conversation_viewer;
    private Gee.Set<Geary.App.Conversation>? prev_selection = null;
    
    public Gtk.Window top_window {
        get { return (Gtk.Window) get_toplevel(); }
    }
    public bool is_active {
        get { return composer != null; }
    }
    
    public ComposerEmbed(ComposerWidget composer, ConversationViewer conversation_viewer,
        Geary.Email? referred) {
        Object(orientation: Gtk.Orientation.VERTICAL);
        this.composer = composer;
        this.conversation_viewer = conversation_viewer;
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
        pack_start(composer, true, true);
        composer.editor.focus_in_event.connect(on_focus_in);
        composer.editor.focus_out_event.connect(on_focus_out);
        conversation_viewer.compose_overlay.add_overlay(this);
        show_all();
        present();
    }
    
    private void on_close() {
        if (composer.should_close() == ComposerWidget.CloseStatus.DO_CLOSE)
            close();
    }
    
    public void on_detach() {
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
    
    public bool set_position(ref Gdk.Rectangle allocation) {
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
        GearyApplication.instance.controller.inline_composer = null;
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

