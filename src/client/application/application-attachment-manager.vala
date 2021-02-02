/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/*
 * Manages downloading and saving email attachment parts.
 */
public class Application.AttachmentManager : GLib.Object {


    public static string untitled_file_name;


    static construct {
        // Translators: File name used in save chooser when saving
        // attachments that do not otherwise have a name.
        AttachmentManager.untitled_file_name = _("Untitled");
    }


    private weak MainWindow parent;


    public AttachmentManager(MainWindow parent) {
        this.parent = parent;
    }

    /**
     * Saves multiple attachments to disk, prompting for destination.
     *
     * Prompt for both a location and for confirmation before
     * overwriting existing files. Files are written with their
     * existing names. Returns true if written to disk, else false.
     */
    public async bool save_attachments(Gee.Collection<Geary.Attachment> attachments,
                                       GLib.Cancellable? cancellable) {
        if (attachments.size == 1) {
            return yield save_attachment(
                Geary.Collection.first(attachments), null, cancellable
            );
        } else {
            return yield save_all(attachments, cancellable);
        }
    }

    /**
     * Saves single attachment to disk, prompting for name and destination.
     *
     * Prompt for both a name and location and for confirmation before
     * overwriting existing files. Returns true if written to disk,
     * else false.
     */
    public async bool save_attachment(Geary.Attachment attachment,
                                      string? alt_name,
                                      GLib.Cancellable? cancellable) {
        string alt_display_name = Geary.String.is_empty_or_whitespace(alt_name)
            ? AttachmentManager.untitled_file_name : alt_name;
        string display_name = yield attachment.get_safe_file_name(
            alt_display_name
        );

        Geary.Memory.Buffer? content = yield open_buffer(
            attachment, cancellable
        );

        bool succeeded = false;
        if (content != null) {
            succeeded = yield this.save_buffer(
                display_name, content, cancellable
            );
        }
        return succeeded;
    }

    /**
     * Saves a buffer to disk as if it was an attachment.
     *
     * Prompt for both a name and location and for confirmation before
     * overwriting existing files. Returns true if written to disk,
     * else false.
     */
    public async bool save_buffer(string display_name,
                                   Geary.Memory.Buffer buffer,
                                   GLib.Cancellable? cancellable) {
        Gtk.FileChooserNative dialog = new_save_chooser(SAVE);
        dialog.set_current_name(display_name);

        string? destination_uri = null;
        if (dialog.run() == Gtk.ResponseType.ACCEPT) {
            destination_uri = dialog.get_uri();
        }
        dialog.destroy();

        bool succeeded = false;
        if (!Geary.String.is_empty_or_whitespace(destination_uri)) {
            succeeded = yield check_and_write(
                buffer, GLib.File.new_for_uri(destination_uri), cancellable
            );
        }
        return succeeded;
    }

    private async bool save_all(Gee.Collection<Geary.Attachment> attachments,
                                GLib.Cancellable? cancellable) {
        var dialog = new_save_chooser(SELECT_FOLDER);
        string? destination_uri = null;
        if (dialog.run() == Gtk.ResponseType.ACCEPT) {
            destination_uri = dialog.get_uri();
        }
        dialog.destroy();

        bool succeeded = false;
        if (!Geary.String.is_empty_or_whitespace(destination_uri)) {
            var destination_dir = GLib.File.new_for_uri(destination_uri);
            foreach (Geary.Attachment attachment in attachments) {
                GLib.File? destination = null;
                try {
                    destination = destination_dir.get_child_for_display_name(
                        yield attachment.get_safe_file_name(
                            AttachmentManager.untitled_file_name
                        )
                    );
                } catch (GLib.IOError.CANCELLED err) {
                    // Everything is going to fail from now on, so get
                    // out of here
                    succeeded = false;
                    break;
                } catch (GLib.Error err) {
                    warning(
                        "Error determining file system name for \"%s\": %s",
                        attachment.file.get_uri(), err.message
                    );
                    handle_error(err);
                }
                var content = yield open_buffer(attachment, cancellable);
                if (content != null &&
                    destination != null) {
                    succeeded &= yield check_and_write(
                        content, destination, cancellable
                    );
                } else {
                    succeeded = false;
                }
            }
        }
        return succeeded;
    }

    private async Geary.Memory.Buffer open_buffer(Geary.Attachment attachment,
                                                  GLib.Cancellable? cancellable) {
        Geary.Memory.FileBuffer? content = null;
        try {
            yield Geary.Nonblocking.Concurrent.global.schedule_async(
                () => {
                    content = new Geary.Memory.FileBuffer(attachment.file, true);
                },
                cancellable
            );
        } catch (GLib.Error err) {
            warning(
                "Error opening attachment file \"%s\": %s",
                attachment.file.get_uri(), err.message
            );
            handle_error(err);
        }
        return content;
    }

    private async bool check_and_write(Geary.Memory.Buffer content,
                                       GLib.File destination,
                                       GLib.Cancellable? cancellable) {
        bool succeeded = false;
        try {
            if (yield check_overwrite(destination, cancellable)) {
                yield write_buffer_to_file(content, destination, cancellable);
                succeeded = true;
            }
        } catch (GLib.Error err) {
            warning(
                "Error saving attachment \"%s\": %s",
                destination.get_uri(), err.message
            );
            handle_error(err);
        }
        return succeeded;
    }

    private async bool check_overwrite(GLib.File to_overwrite,
                                       GLib.Cancellable? cancellable)
        throws GLib.Error {
        string target_name = "";
        string parent_name = "";
        try {
            GLib.FileInfo file_info = yield to_overwrite.query_info_async(
                GLib.FileAttribute.STANDARD_DISPLAY_NAME,
                GLib.FileQueryInfoFlags.NONE,
                GLib.Priority.DEFAULT,
                cancellable
            );
            target_name = file_info.get_display_name();
            GLib.FileInfo parent_info = yield to_overwrite.get_parent()
                .query_info_async(
                    GLib.FileAttribute.STANDARD_DISPLAY_NAME,
                    GLib.FileQueryInfoFlags.NONE,
                    GLib.Priority.DEFAULT,
                    cancellable
                );
            parent_name = parent_info.get_display_name();
        } catch (GLib.IOError.NOT_FOUND err) {
            // All good
            return true;
        }

        /// Translators: Dialog primary label when prompting to
        /// overwrite a file. The string substitution is the file'sx
        /// name.
        string primary = _(
            "A file named “%s” already exists.  Do you want to replace it?"
        ).printf(target_name);

        /// Translators: Dialog secondary label when prompting to
        /// overwrite a file. The string substitution is the parent
        /// folder's name.
        string secondary = _(
            "The file already exists in “%s”.  Replacing it will overwrite its contents."
        ).printf(parent_name);

        ConfirmationDialog dialog = new ConfirmationDialog(
            this.parent,
            primary,
            secondary,
            _("_Replace"),
            "destructive-action"
        );
        return (dialog.run() == Gtk.ResponseType.OK);
    }

    private async void write_buffer_to_file(Geary.Memory.Buffer buffer,
                                           GLib.File destination,
                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        try {
            GLib.FileOutputStream outs = destination.replace(
                null, false, REPLACE_DESTINATION, cancellable
            );
            yield outs.splice_async(
                buffer.get_input_stream(),
                CLOSE_SOURCE | CLOSE_TARGET,
                GLib.Priority.DEFAULT,
                cancellable
            );
        } catch (GLib.IOError.CANCELLED err) {
            try {
                yield destination.delete_async(GLib.Priority.HIGH, null);
            } catch (GLib.Error err) {
                // Oh well
            }
            throw err;
        }
    }

    private inline Gtk.FileChooserNative new_save_chooser(Gtk.FileChooserAction action) {
        Gtk.FileChooserNative dialog = new Gtk.FileChooserNative(
            null,
            this.parent,
            action,
            Stock._SAVE,
            Stock._CANCEL
        );
        var download_dir = GLib.Environment.get_user_special_dir(DOWNLOAD);
        if (!Geary.String.is_empty_or_whitespace(download_dir)) {
            dialog.set_current_folder(download_dir);
        }
        dialog.set_local_only(false);
        return dialog;
    }

    private inline void handle_error(GLib.Error error) {
        this.parent.application.controller.report_problem(
            new Geary.ProblemReport(error)
        );
    }

}
