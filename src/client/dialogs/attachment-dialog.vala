/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class AttachmentDialog : Gtk.FileChooserDialog {
    private static const int PREVIEW_SIZE = 180;
    private static const int PREVIEW_PADDING = 3;
    
    private static string? current_folder = null;
    
    private Gtk.Image preview_image;
    
    public delegate bool Attacher(File attachment_file, bool alert_errors = true);

    public AttachmentDialog(Gtk.Window? parent) {
        Object(title: _("Choose a file"), transient_for: parent, action: Gtk.FileChooserAction.OPEN);
    }
    
    construct {
        add_button(Stock._CANCEL, Gtk.ResponseType.CANCEL);
        add_button(_("_Attach"), Gtk.ResponseType.ACCEPT);

        if (!Geary.String.is_empty(current_folder)) {
            set_current_folder(current_folder);
        }
        set_local_only(false);
        set_select_multiple(true);
        
        preview_image = new Gtk.Image();
        set_preview_widget(preview_image);
        use_preview_label = false;
        
        update_preview.connect(on_update_preview);
    }
    
    public bool is_finished(Attacher add_attachment) {
        if (run() != Gtk.ResponseType.ACCEPT) {
            destroy();
            return true;
        }
        current_folder = get_current_folder();
        foreach (File file in get_files()) {
            if (!add_attachment(file)) {
                destroy();
                return false;
            }
        }
        destroy();
        return true;
    }
    
    private void on_update_preview() {
        string? filename = get_preview_filename();
        if (filename == null) {
            set_preview_widget_active(false);
            return;
        }
        
        // read the image format data first
        int width = 0;
        int height = 0;
        Gdk.PixbufFormat? format = Gdk.Pixbuf.get_file_info(filename, out width, out height);
        
        if (format == null) {
            set_preview_widget_active(false);
            return;
        }
        
        // if the image is too big, resize it
        Gdk.Pixbuf pixbuf;
        try {
            if (width > PREVIEW_SIZE || height > PREVIEW_SIZE) {
                pixbuf = new Gdk.Pixbuf.from_file_at_size(filename, PREVIEW_SIZE, PREVIEW_SIZE);
            } else {
                pixbuf = new Gdk.Pixbuf.from_file(filename);
            }
        } catch (Error e) {
            set_preview_widget_active(false);
            return;
        }
        
        if (pixbuf == null) {
            set_preview_widget_active(false);
            return;
        }
        
        pixbuf = pixbuf.apply_embedded_orientation();
        
        // distribute the extra space around the image
        int extra_space = PREVIEW_SIZE - pixbuf.width;
        int smaller_half = extra_space/2;
        int larger_half = extra_space - smaller_half;
        
        // pad the image manually (avoids rounding errors)
        preview_image.set_margin_left(PREVIEW_PADDING + smaller_half);
        preview_image.set_margin_right(PREVIEW_PADDING + larger_half);
        
        // show the preview
        preview_image.set_from_pixbuf(pixbuf);
        set_preview_widget_active(true);
    }
}
