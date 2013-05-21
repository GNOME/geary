/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ComposerEmbed : Gtk.Box, ComposerContainer {
    
    public ulong signal_id;
    private string embed_id;
    private ComposerWidget composer;
    
    public Gtk.Window top_window {
        get { return (Gtk.Window) get_toplevel(); }
    }
    
    private static ConversationViewer conversation_viewer {
        get { return GearyApplication.instance.controller.main_window.conversation_viewer; }
    }
    
    public static bool create_embed(ComposerWidget composer, Geary.Email? referred) {
        if (referred == null)
            return false;
        
        WebKit.DOM.HTMLElement? email_element = conversation_viewer.web_view.get_dom_document()
            .get_element_by_id(conversation_viewer.get_div_id(referred.id)) as WebKit.DOM.HTMLElement;
        if (email_element == null)
            return false;
        
        string id = "%x".printf(Random.next_int());
        ComposerEmbed plugin = new ComposerEmbed(id);
        plugin.signal_id = conversation_viewer.web_view.create_plugin_widget.connect(() => {
            conversation_viewer.web_view.disconnect(plugin.signal_id);
            return plugin;
        });
        
        try {
            conversation_viewer.web_view.settings.enable_plugins = true;
            email_element.insert_adjacent_html("afterend",
                @"<embed width='100%' height='600' type='composer' id='$id' />");
        } catch (Error error) {
            debug("Error creating embed element: %s", error.message);
            return false;
        } finally {
            conversation_viewer.web_view.settings.enable_plugins = false;
        }
        plugin.insert_composer(composer);
        return true;
    }
    
    public ComposerEmbed(string embed_id) {
        Object(orientation: Gtk.Orientation.VERTICAL);
        this.embed_id = embed_id;
        
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
        
        close.clicked.connect(on_close);
        detach.clicked.connect(on_detach);
    }
    
    private void insert_composer(ComposerWidget composer) {
        pack_start(composer, true, true);
        show_all();
        this.composer = composer;
    }
    
    private void on_close() {
        if (composer.should_close())
            close();
    }
    
    private void on_detach() {
        remove(composer);
        new ComposerWindow(composer);
        close();
    }
    
    public void present() {
        conversation_viewer.web_view.get_dom_document().get_element_by_id(embed_id).scroll_into_view(true);
    }
    
    public unowned Gtk.Widget get_focus() {
        return top_window.get_focus();
    }
    
    private void close() {
        WebKit.DOM.Element embed = conversation_viewer.web_view.get_dom_document().get_element_by_id(embed_id);
        try{
            embed.parent_element.remove_child(embed);
        } catch (Error error) {
            warning("Could not remove embed from WebView: %s", error.message);
        }
        destroy();  // We seem to need this to ensure the ComposerWidget is destroyed.
    }
}

