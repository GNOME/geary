/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.Attachment : Geary.Attachment {


    public const Email.Field REQUIRED_FIELDS = Email.REQUIRED_FOR_MESSAGE;

    private const string NULL_FILE_NAME = "none";


    internal int64 message_id { get; private set; }

    private int64 attachment_id = -1;


    private Attachment(int64 message_id,
                       Mime.ContentType content_type,
                       string? content_id,
                       string? content_description,
                       Mime.ContentDisposition content_disposition,
                       string? content_filename) {
        base(
            content_type,
            content_id,
            content_description,
            content_disposition,
            content_filename
        );

        this.message_id = message_id;
    }

    internal Attachment.from_part(int64 message_id, RFC822.Part part)
        throws Error {
        Mime.ContentDisposition? disposition = part.content_disposition;
        if (disposition == null) {
            disposition = new Mime.ContentDisposition.simple(
                Geary.Mime.DispositionType.UNSPECIFIED
            );
        }

        this(
            message_id,
            part.content_type,
            part.content_id,
            part.content_description,
            disposition,
            part.get_clean_filename()
        );
    }

    internal Attachment.from_row(Geary.Db.Result result, File attachments_dir)
        throws Error {
        string? content_filename = result.string_for("filename");
        if (content_filename == ImapDB.Attachment.NULL_FILE_NAME) {
            // Prior to 0.12, Geary would store the untranslated
            // string "none" as the filename when none was
            // specified by the MIME content disposition. Check
            // for that and clean it up.
            content_filename = null;
        }

        Mime.ContentDisposition disposition = new Mime.ContentDisposition.simple(
            Mime.DispositionType.from_int(result.int_for("disposition"))
        );

        this(
            result.rowid_for("message_id"),
            Mime.ContentType.parse(result.nonnull_string_for("mime_type")),
            result.string_for("content_id"),
            result.string_for("description"),
            disposition,
            content_filename
        );

        this.attachment_id = result.rowid_for("id");

        set_file_info(
            generate_file(attachments_dir), result.int64_for("filesize")
        );
    }

    internal void save(Db.Connection cx,
                       RFC822.Part part,
                       GLib.File attachments_dir,
                       Cancellable? cancellable)
        throws Error {
        insert_db(cx, cancellable);
        try {
            save_file(part, attachments_dir, cancellable);
            update_db(cx, cancellable);
        } catch (Error err) {
            // Don't honour the cancellable here, it needs to be
            // deleted
            this.delete(cx, null);
            throw err;
        }
    }

    // This isn't async since its only callpaths are via db async
    // transactions, which run in independent threads.
    internal void delete(Db.Connection cx, Cancellable? cancellable) {
        if (this.attachment_id >= 0) {
            try {
                Db.Statement remove_stmt = cx.prepare(
                    "DELETE FROM MessageAttachmentTable WHERE id=?");
                remove_stmt.bind_rowid(0, this.attachment_id);

                remove_stmt.exec();
            } catch (Error err) {
                debug("Error attempting to remove added attachment row for %s: %s",
                      this.file.get_path(), err.message);
            }
        }

        if (this.file != null) {
            try {
                this.file.delete(cancellable);
            } catch (Error err) {
                debug("Error attempting to remove attachment file %s: %s",
                      this.file.get_path(), err.message);
            }
        }
    }

    private void insert_db(Db.Connection cx, Cancellable? cancellable)
        throws Error {
        // Insert it into the database.
        Db.Statement stmt = cx.prepare("""
                INSERT INTO MessageAttachmentTable (message_id, filename, mime_type, filesize, disposition, content_id, description)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """);
        stmt.bind_rowid(0, this.message_id);
        stmt.bind_string(1, this.content_filename);
        stmt.bind_string(2, this.content_type.to_string());
        stmt.bind_int64(3, 0); // This is updated after saving the file
        stmt.bind_int(4, this.content_disposition.disposition_type);
        stmt.bind_string(5, this.content_id);
        stmt.bind_string(6, this.content_description);

        this.attachment_id = stmt.exec_insert(cancellable);
    }

    // This isn't async since its only callpaths are via db async
    // transactions, which run in independent threads
    private void save_file(RFC822.Part part,
                           GLib.File attachments_dir,
                           Cancellable? cancellable)
        throws Error {
        if (this.attachment_id < 0) {
            throw new IOError.NOT_FOUND("No attachment id assigned");
        }

        File target = generate_file(attachments_dir);

        // create directory, but don't throw exception if already exists
        try {
            target.get_parent().make_directory_with_parents(cancellable);
        } catch (IOError.EXISTS err) {
            // All good
        }

        // Delete any existing file now since we might not be creating
        // it again below.
        try {
            target.delete(cancellable);
        } catch (IOError err) {
            // All good
        }

        GLib.OutputStream target_stream = target.create(
            FileCreateFlags.NONE, cancellable
        );
        GMime.Stream stream = new Geary.Stream.MimeOutputStream(
            target_stream
        );
        stream = new GMime.StreamBuffer(
            stream, GMime.StreamBufferMode.WRITE
        );

        part.write_to_stream(stream, RFC822.Part.EncodingConversion.NONE);

        // Using the stream's length is a bit of a hack, but at
        // least on one system we are getting 0 back for the file
        // size if we use target.query_info().
        int64 file_size = stream.length();

        stream.close();

        set_file_info(target, file_size);
    }

    private void update_db(Db.Connection cx, Cancellable? cancellable)
        throws Error {
        // Update the file size now we know what it is
        Db.Statement stmt = cx.prepare("""
            UPDATE MessageAttachmentTable
            SET filesize = ?
            WHERE id = ?
        """);
        stmt.bind_int64(0, this.filesize);
        stmt.bind_rowid(1, this.attachment_id);

        stmt.exec(cancellable);
    }

    private GLib.File generate_file(GLib.File attachments_dir) {
        return attachments_dir
            .get_child(this.message_id.to_string())
            .get_child(this.attachment_id.to_string())
            .get_child(this.content_filename ?? NULL_FILE_NAME);
    }


    internal static Gee.List<Attachment> save_attachments(Db.Connection cx,
                                                          GLib.File attachments_path,
                                                          int64 message_id,
                                                          Gee.List<RFC822.Part> attachments,
                                                          Cancellable? cancellable)
        throws Error {
        Gee.List<Attachment> list = new Gee.LinkedList<Attachment>();
        foreach (RFC822.Part part in attachments) {
            Attachment attachment = new Attachment.from_part(message_id, part);
            attachment.save(cx, part, attachments_path, cancellable);
            list.add(attachment);
        }
        return list;
    }

    internal static void delete_attachments(Db.Connection cx,
                                            GLib.File attachments_path,
                                            int64 message_id,
                                            Cancellable? cancellable = null)
        throws Error {
        Gee.List<Attachment>? attachments = list_attachments(
            cx, attachments_path, message_id, cancellable
        );
        foreach (Attachment attachment in attachments) {
            attachment.delete(cx, cancellable);
        }

        // Ensure they're dead, Jim.
        Db.Statement stmt = cx.prepare("""
            DELETE FROM MessageAttachmentTable WHERE message_id = ?
        """);
        stmt.bind_rowid(0, message_id);
        stmt.exec();
    }

    // XXX this really should be a member of some internal
    // ImapDB.Email class.
    internal static void add_attachments(Db.Connection cx,
                                         GLib.File attachments_path,
                                         Geary.Email email,
                                         int64 message_id,
                                         Cancellable? cancellable = null)
        throws Error {
        if (email.fields.fulfills(ImapDB.Attachment.REQUIRED_FIELDS)) {
            email.add_attachments(
                list_attachments(
                    cx, attachments_path, message_id, cancellable
                )
            );
        }
    }

    internal static Gee.List<Attachment> list_attachments(Db.Connection cx,
                                                          GLib.File attachments_path,
                                                          int64 message_id,
                                                          Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare("""
            SELECT *
            FROM MessageAttachmentTable
            WHERE message_id = ?
            ORDER BY id
            """);
        stmt.bind_rowid(0, message_id);
        Db.Result results = stmt.exec(cancellable);

        Gee.List<Attachment> list = new Gee.LinkedList<Attachment>();
        while (!results.finished) {
            list.add(new ImapDB.Attachment.from_row(results, attachments_path));
            results.next(cancellable);
        }
        return list;
    }

}
