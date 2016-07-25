/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A ComposerBox is a ComposerContainer that is used to compose mails in the main-window
 * (i.e. not-detached), yet separate from a conversation.
 */
public class ComposerBox : Gtk.Frame, ComposerContainer {

    public Gtk.ApplicationWindow top_window {
        get { return (Gtk.ApplicationWindow) get_toplevel(); }
    }

    protected ComposerWidget composer { get; set; }

    protected Gee.MultiMap<string, string>? old_accelerators { get; set; }


    public signal void vanished();


    public ComposerBox(ComposerWidget composer) {
        this.composer = composer;

        add(this.composer);
        this.composer.editor.focus_in_event.connect(on_focus_in);
        this.composer.editor.focus_out_event.connect(on_focus_out);
        show();

        get_style_context().add_class("geary-composer-box");

        if (this.composer.state == ComposerWidget.ComposerState.NEW) {
            this.composer.free_header();
            GearyApplication.instance.controller.main_window.main_toolbar.set_conversation_header(
                composer.header);
            get_style_context().add_class("geary-full-pane");
        }
    }

    public void remove_composer() {
        if (this.composer.editor.has_focus)
            on_focus_out();
        this.composer.editor.focus_in_event.disconnect(on_focus_in);
        this.composer.editor.focus_out_event.disconnect(on_focus_out);

        remove(this.composer);
        close_container();
    }

    public void vanish() {
        hide();
        if (get_style_context().has_class("geary-full-pane"))
            GearyApplication.instance.controller.main_window.main_toolbar.remove_conversation_header(
                composer.header);
        this.composer.state = ComposerWidget.ComposerState.DETACHED;
        this.composer.editor.focus_in_event.disconnect(on_focus_in);
        this.composer.editor.focus_out_event.disconnect(on_focus_out);

        vanished();
    }

    public void close_container() {
        if (visible)
            vanish();
    }
}

