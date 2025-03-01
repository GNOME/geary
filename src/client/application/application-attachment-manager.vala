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
        var dialog = new Gtk.FileDialog();
        dialog.initial_name = display_name;
        dialog.initial_folder = download_dir();

        File? destination = null;
        try {
            destination = yield dialog.save(this.parent, cancellable);
        } catch (Error err) {
            //XXX GTK4 check if cancelled is accidentally caught here as well
            warning("Couldn't select file to save attachment: %s", err.message);
            return false;
        }

        return yield check_and_write(buffer, destination, cancellable);
    }

    private async bool save_all(Gee.Collection<Geary.Attachment> attachments,
                                GLib.Cancellable? cancellable) {
        var dialog = new Gtk.FileDialog();
        dialog.initial_file = download_dir();

        File? destination_dir = null;
        try {
            destination_dir = yield dialog.select_folder(this.parent, cancellable);
        } catch (Error err) {
            //XXX GTK4 check if cancelled is accidentally caught here as well
            warning("Couldn't select folder for saving attachments: %s", err.message);
            return false;
        }

        if (destination_dir == null)
            return false;

        bool succeeded = false;
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

        var dialog = new Adw.AlertDialog(primary, secondary);
        dialog.add_responses(
            "replace", _("_Replace"),
            "cancel", _("_Cancel"),
            null
        );
        dialog.default_response = "cancel";
        dialog.close_response = "cancel";
        dialog.set_response_appearance("replace", Adw.ResponseAppearance.DESTRUCTIVE);
        string response = yield dialog.choose(this.parent, cancellable);

        return (response == "replace");
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

    private File? download_dir() {
        var download_dir = GLib.Environment.get_user_special_dir(DOWNLOAD);
        if (Geary.String.is_empty_or_whitespace(download_dir))
            return null;
        return File.new_for_path(download_dir);
    }

    private inline void handle_error(GLib.Error error) {
        this.parent.application.controller.report_problem(
            new Geary.ProblemReport(error)
        );
    }

}
