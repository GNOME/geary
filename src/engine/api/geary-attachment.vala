/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An attachment that was a part of an {@link Email}.
 */
public abstract class Geary.Attachment : BaseObject {


    /**
     * The {@link Mime.ContentType} of the {@link Attachment}.
     */
    public Mime.ContentType content_type { get; private set; }

    /**
     * The Content-ID of the attachment.
     *
     * See [[https://tools.ietf.org/html/rfc2111]]
     *
     * @see Email.get_attachment_by_content_id
     */
    public string? content_id { get; private set; }

    /**
     * The Content-Description of the attachment.
     *
     * See [[https://tools.ietf.org/html/rfc2045#section-8]]
     */
    public string? content_description { get; private set; }

    /**
     * The {@link Mime.ContentDisposition} of the attachment, as specified by the {@link Email}.
     *
     * See [[https://tools.ietf.org/html/rfc2183]]
     */
    public Mime.ContentDisposition content_disposition { get; private set; }

    /**
     * Returns true if a filename was supplied in {@link content_disposition}.
     *
     * Since all files must have a name, one is supplied for the
     * Attachment by Geary if this is false.  This is merely to
     * indicate how the filename should be displayed, since Geary's
     * will be an untranslated "none".
     */
    public bool has_content_filename { get { return this.content_filename != null; } }

    /**
     * The filename supplied in {@link content_disposition}, if any.
     */
    public string? content_filename { get; private set; }

    /**
     * The attachment's on-disk File, if any.
     *
     * This will be null if the attachment has not been saved to disk.
     */
    public GLib.File? file { get; private set; default = null; }

    /**
     * The file size (in bytes) if the {@link file}.
     *
     * This will be -1 if the attachment has not been saved to disk.
     */
    public int64 filesize { get; private set; default = -1; }


    protected Attachment(Mime.ContentType content_type,
                         string? content_id,
                         string? content_description,
                         Mime.ContentDisposition content_disposition,
                         string? content_filename) {
        this.content_type = content_type;
        this.content_id = content_id;
        this.content_description = content_description;
        this.content_disposition = content_disposition;
        this.content_filename = content_filename;
    }

    /**
     * Returns a string to use as a file name, even if not specified.
     *
     * This checks that the extension of the given content file name
     * matches the given content type, even if the attachment has the
     * default content type.
     *
     * If no file name was specified for the attachment, it will
     * construct one from the attachment's id and by guessing the file
     * name extension, and also guessing the MIME content type if
     * needed.
     *
     * If a file name is constructed and a non-empty value for the
     * `alt_file_name` parameter is specified, then that will be used
     * in preference over the content id and attachment id.
     */
    public async string get_safe_file_name(string? alt_file_name = null) {
        string? file_name = this.content_filename;
        if (Geary.String.is_empty(file_name)) {
            string[] others = {
                alt_file_name,
                this.content_id,
                "attachment",
            };

            int i = 0;
            while (Geary.String.is_empty(file_name)) {
                file_name = others[i++];
            }
        }

        file_name = file_name.strip();

        // Check the content type suggested by the file name is
        // consistent with the declared content type. This adds an
        // appropriate file name extension if missing, and ensures
        // that malicious file names are fixed up.
        Mime.ContentType mime_type = this.content_type;
        Mime.ContentType? name_type = null;
        try {
            name_type = Mime.ContentType.guess_type(file_name, null);
        } catch (Error err) {
            debug("Error guessing attachment file name content type: %s", err.message);
        }

        if (name_type == null ||
            name_type.is_same(Mime.ContentType.ATTACHMENT_DEFAULT) ||
            !name_type.is_same(mime_type)) {
            // Substitute file name either is of unknown type
            // (e.g. it does not have an extension) or is not the
            // same type as the declared type, so try to fix it.
            if (mime_type.is_same(Mime.ContentType.ATTACHMENT_DEFAULT)) {
                // Declared type is unknown, see if we can guess
                // it. Don't use GFile.query_info however since
                // that will attempt to use the filename, which is
                // what we are trying to guess in the first place.
                try {
                    mime_type = Mime.ContentType.guess_type(
                        null,
                        new Geary.Memory.FileBuffer(this.file, true)
                    );
                } catch (Error err) {
                    debug("Error guessing attachment data content type: %s", err.message);
                }
            }
            string? ext = mime_type.get_file_name_extension();
            if (ext != null && !file_name.has_suffix(ext)) {
                file_name = file_name + (ext ?? "");
            }
        }
        return file_name;
    }

    /**
     * Sets the attachment's on-disk location and size.
     */
    protected void set_file_info(GLib.File file, int64 file_size) {
        this.file = file;
        this.filesize = file_size;
    }

}
