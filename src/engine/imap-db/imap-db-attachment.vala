/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.Attachment : Geary.Attachment {
    public const Email.Field REQUIRED_FIELDS = Email.REQUIRED_FOR_MESSAGE;

    internal const string NULL_FILE_NAME = "none";

    public Attachment(int64 message_id,
                      int64 attachment_id,
                      Mime.ContentType content_type,
                      string? content_id,
                      string? content_description,
                      Mime.ContentDisposition content_disposition,
                      string? content_filename,
                      File data_dir,
                      int64 filesize) {
        base (generate_id(attachment_id),
              content_type,
              content_id,
              content_description,
              content_disposition,
              content_filename,
              generate_file(data_dir, message_id, attachment_id, content_filename),
              filesize);
    }

    private static string generate_id(int64 attachment_id) {
        return "imap-db:%s".printf(attachment_id.to_string());
    }

    public static File generate_file(File attachements_dir, int64 message_id, int64 attachment_id,
        string? filename) {
        return attachements_dir
            .get_child(message_id.to_string())
            .get_child(attachment_id.to_string())
            .get_child(filename ?? NULL_FILE_NAME);
    }

    internal static void do_save_attachments(Db.Connection cx,
                                             GLib.File attachments_path,
                                             int64 message_id,
                                             Gee.List<GMime.Part>? attachments,
                                             Cancellable? cancellable)
        throws Error {
        // nothing to do if no attachments
        if (attachments == null || attachments.size == 0)
            return;

        foreach (GMime.Part attachment in attachments) {
            GMime.ContentType? content_type = attachment.get_content_type();
            string mime_type = (content_type != null)
                ? content_type.to_string()
                : Mime.ContentType.DEFAULT_CONTENT_TYPE;
            string? disposition = attachment.get_disposition();
            string? content_id = attachment.get_content_id();
            string? description = attachment.get_content_description();
            string? filename = RFC822.Utils.get_clean_attachment_filename(attachment);

            // Convert the attachment content into a usable ByteArray.
            GMime.DataWrapper? attachment_data = attachment.get_content_object();
            ByteArray byte_array = new ByteArray();
            GMime.StreamMem stream = new GMime.StreamMem.with_byte_array(byte_array);
            stream.set_owner(false);
            if (attachment_data != null)
                attachment_data.write_to_stream(stream); // data is null if it's 0 bytes
            uint filesize = byte_array.len;

            // convert into DispositionType enum, which is stored as int
            // (legacy code stored UNSPECIFIED as NULL, which is zero, which is ATTACHMENT, so preserve
            // this behavior)
            Mime.DispositionType disposition_type = Mime.DispositionType.deserialize(disposition,
                null);
            if (disposition_type == Mime.DispositionType.UNSPECIFIED)
                disposition_type = Mime.DispositionType.ATTACHMENT;

            // Insert it into the database.
            Db.Statement stmt = cx.prepare("""
                INSERT INTO MessageAttachmentTable (message_id, filename, mime_type, filesize, disposition, content_id, description)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """);
            stmt.bind_rowid(0, message_id);
            stmt.bind_string(1, filename);
            stmt.bind_string(2, mime_type);
            stmt.bind_uint(3, filesize);
            stmt.bind_int(4, disposition_type);
            stmt.bind_string(5, content_id);
            stmt.bind_string(6, description);

            int64 attachment_id = stmt.exec_insert(cancellable);
            File saved_file = ImapDB.Attachment.generate_file(
                attachments_path, message_id, attachment_id, filename
            );

            // On the off-chance this is marked for deletion, unmark it
            try {
                stmt = cx.prepare("""
                    DELETE FROM DeleteAttachmentFileTable
                    WHERE filename = ?
                """);
                stmt.bind_string(0, saved_file.get_path());

                stmt.exec(cancellable);
            } catch (Error err) {
                debug("Unable to delete from DeleteAttachmentFileTable: %s", err.message);

                // not a deal-breaker, fall through
            }

            debug("Saving attachment to %s", saved_file.get_path());

            try {
                // create directory, but don't throw exception if already exists
                try {
                    saved_file.get_parent().make_directory_with_parents(cancellable);
                } catch (IOError ioe) {
                    // fall through if already exists
                    if (!(ioe is IOError.EXISTS))
                        throw ioe;
                }

                // REPLACE_DESTINATION doesn't seem to work as advertised all the time ... just
                // play it safe here
                if (saved_file.query_exists(cancellable))
                    saved_file.delete(cancellable);

                // Create the file where the attachment will be saved and get the output stream.
                FileOutputStream saved_stream = saved_file.create(FileCreateFlags.REPLACE_DESTINATION,
                    cancellable);

                // Save the data to disk and flush it.
                size_t written;
                if (filesize != 0)
                    saved_stream.write_all(byte_array.data[0:filesize], out written, cancellable);

                saved_stream.flush(cancellable);
            } catch (Error error) {
                // An error occurred while saving the attachment, so lets remove the attachment from
                // the database and delete the file (in case it's partially written)
                debug("Failed to save attachment %s: %s", saved_file.get_path(), error.message);

                try {
                    saved_file.delete();
                } catch (Error delete_error) {
                    debug("Error attempting to delete partial attachment %s: %s", saved_file.get_path(),
                        delete_error.message);
                }

                try {
                    Db.Statement remove_stmt = cx.prepare(
                        "DELETE FROM MessageAttachmentTable WHERE id=?");
                    remove_stmt.bind_rowid(0, attachment_id);

                    remove_stmt.exec();
                } catch (Error remove_error) {
                    debug("Error attempting to remove added attachment row for %s: %s",
                        saved_file.get_path(), remove_error.message);
                }

                throw error;
            }
        }
    }

    internal static void do_delete_attachments(Db.Connection cx,
                                               GLib.File attachments_path,
                                               int64 message_id)
        throws Error {
        Gee.List<Geary.Attachment>? attachments = do_list_attachments(
            cx, attachments_path, message_id, null
        );
        if (attachments == null || attachments.size == 0)
            return;

        // delete all files
        foreach (Geary.Attachment attachment in attachments) {
            try {
                attachment.file.delete(null);
            } catch (Error err) {
                debug("Unable to delete file %s: %s", attachment.file.get_path(), err.message);
            }
        }

        // remove all from attachment table
        Db.Statement stmt = new Db.Statement(cx, """
            DELETE FROM MessageAttachmentTable WHERE message_id = ?
        """);
        stmt.bind_rowid(0, message_id);

        stmt.exec();
    }

    internal static Geary.Email do_add_attachments(Db.Connection cx,
                                                   GLib.File attachments_path,
                                                   Geary.Email email,
                                                   int64 message_id,
                                                   Cancellable? cancellable = null)
        throws Error {
        // Add attachments if available
        if (email.fields.fulfills(ImapDB.Attachment.REQUIRED_FIELDS)) {
            Gee.List<Geary.Attachment>? attachments = do_list_attachments(
                cx, attachments_path, message_id, cancellable
            );
            if (attachments != null)
                email.add_attachments(attachments);
        }

        return email;
    }

    private static Gee.List<Geary.Attachment>?
        do_list_attachments(Db.Connection cx,
                            GLib.File attachments_path,
                            int64 message_id,
                            Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare("""
            SELECT id, filename, mime_type, filesize, disposition, content_id, description
            FROM MessageAttachmentTable
            WHERE message_id = ?
            ORDER BY id
            """);
        stmt.bind_rowid(0, message_id);

        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return null;

        Gee.List<Geary.Attachment> list = new Gee.ArrayList<Geary.Attachment>();
        do {
            string? content_filename = results.string_at(1);
            if (content_filename == ImapDB.Attachment.NULL_FILE_NAME) {
                // Prior to 0.12, Geary would store the untranslated
                // string "none" as the filename when none was
                // specified by the MIME content disposition. Check
                // for that and clean it up.
                content_filename = null;
            }
            Mime.ContentDisposition disposition = new Mime.ContentDisposition.simple(
                Mime.DispositionType.from_int(results.int_at(4)));
            list.add(
                new ImapDB.Attachment(
                    message_id,
                    results.rowid_at(0),
                    Mime.ContentType.deserialize(results.nonnull_string_at(2)),
                    results.string_at(5),
                    results.string_at(6),
                    disposition,
                    content_filename,
                    attachments_path,
                    results.int64_at(3)
                )
            );
        } while (results.next(cancellable));

        return list;
    }

}
