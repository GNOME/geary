/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A FileChooser-like object for choosing attachments for a message.
 */
public class AttachmentDialog : Object {

    private const int PREVIEW_SIZE = 180;
    private const int PREVIEW_PADDING = 3;

    private Application.Configuration config;

    private Gtk.FileChooserNative? chooser = null;

    private Gtk.Image preview_image = new Gtk.Image();

    public delegate bool Attacher(File attachment_file, bool alert_errors = true);

    public AttachmentDialog(Gtk.Window? parent, Application.Configuration config) {
        this.config = config;
        this.chooser = new Gtk.FileChooserNative(_("Choose a file"), parent, Gtk.FileChooserAction.OPEN, _("_Attach"), Stock._CANCEL);

        this.chooser.set_local_only(false);
        this.chooser.set_select_multiple(true);

        // preview widget is not supported on Win32 (this will fallback to gtk file chooser)
        // and possibly by some org.freedesktop.portal.FileChooser (preview will be ignored).
        this.chooser.set_preview_widget(this.preview_image);
        this.chooser.use_preview_label = false;

        this.chooser.update_preview.connect(on_update_preview);
    }

    public void add_filter(owned Gtk.FileFilter filter) {
        this.chooser.add_filter(filter);
    }

    public SList<File> get_files() {
        return this.chooser.get_files();
    }

    public int run() {
        return this.chooser.run();
    }

    public void hide() {
        this.chooser.hide();
    }

    public void destroy() {
        this.chooser.destroy();
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
