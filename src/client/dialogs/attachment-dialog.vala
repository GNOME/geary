/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class AttachmentDialog : Object {
#if GTK_3_20
    private Gtk.FileChooserNative? chooser = null;
#else
    private Gtk.FileChooserDialog? chooser = null;
#endif
    private const int PREVIEW_SIZE = 180;
    private const int PREVIEW_PADDING = 3;
    
    private static string? current_folder = null;
    
    private Gtk.Image preview_image;
    
    public delegate bool Attacher(File attachment_file, bool alert_errors = true);

    public AttachmentDialog(Gtk.Window? parent) {
#if GTK_3_20
        chooser = new Gtk.FileChooserNative(_("Choose a file"), parent, Gtk.FileChooserAction.OPEN, _("_Attach"), Stock._CANCEL);
#else
        chooser = new Gtk.FileChooserDialog(_("Choose a file"), parent, Gtk.FileChooserAction.OPEN, Stock._CANCEL, Gtk.ResponseType.CANCEL, _("_Attach"), Gtk.ResponseType.ACCEPT);
#endif

        if (!Geary.String.is_empty(current_folder)) {
            chooser.set_current_folder(current_folder);
        }
        chooser.set_local_only(false);
        chooser.set_select_multiple(true);

        // preview widget is not supported on Win32 (this will fallback to gtk file chooser)
        // and possibly by some org.freedesktop.portal.FileChooser (preview will be ignored).
        preview_image = new Gtk.Image();
        chooser.set_preview_widget(preview_image);
        chooser.use_preview_label = false;

        chooser.update_preview.connect(on_update_preview);
    }
    
    public bool is_finished(Attacher add_attachment) {
        if (chooser.run() != Gtk.ResponseType.ACCEPT) {
            chooser.destroy();
            return true;
        }
        current_folder = chooser.get_current_folder();
        foreach (File file in chooser.get_files()) {
            if (!add_attachment(file)) {
                chooser.destroy();
                return false;
            }
        }
        chooser.destroy();
        return true;
    }
    
    private void on_update_preview() {
        string? filename = chooser.get_preview_filename();
        if (filename == null) {
            chooser.set_preview_widget_active(false);
            return;
        }
        
        // read the image format data first
        int width = 0;
        int height = 0;
        Gdk.PixbufFormat? format = Gdk.Pixbuf.get_file_info(filename, out width, out height);
        
        if (format == null) {
            chooser.set_preview_widget_active(false);
            return;
        }
        
        // if the image is too big, resize it
        Gdk.Pixbuf pixbuf;
        try {
            pixbuf = new Gdk.Pixbuf.from_file_at_scale(filename, PREVIEW_SIZE, PREVIEW_SIZE, true);
        } catch (Error e) {
            chooser.set_preview_widget_active(false);
            return;
        }
        
        if (pixbuf == null) {
            chooser.set_preview_widget_active(false);
            return;
        }
        
        pixbuf = pixbuf.apply_embedded_orientation();
        
        // distribute the extra space around the image
        int extra_space = PREVIEW_SIZE - pixbuf.width;
        int smaller_half = extra_space/2;
        int larger_half = extra_space - smaller_half;
        
        // pad the image manually (avoids rounding errors)
        preview_image.set_margin_start(PREVIEW_PADDING + smaller_half);
        preview_image.set_margin_end(PREVIEW_PADDING + larger_half);
        
        // show the preview
        preview_image.set_from_pixbuf(pixbuf);
        chooser.set_preview_widget_active(true);
    }
}
