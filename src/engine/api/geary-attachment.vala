/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An attachment that was a part of an {@link Email}.
 *
 * @see Email.get_attachment
 */

public abstract class Geary.Attachment : BaseObject {

    /**
     * An identifier that can be used to locate the {@link Attachment} in an {@link Email}.
     *
     * @see Email.get_attachment
     */
    public string id { get; private set; }

    /**
     * The {@link Mime.ContentType} of the {@link Attachment}.
     */
    public Mime.ContentType content_type { get; private set; }

    /**
     * The Content-ID of the attachment.
     *
     * See [[https://tools.ietf.org/html/rfc2111]]
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
     * The on-disk File of the {@link Attachment}.
     */
    public File file { get; private set; }

    /**
     * The file size (in bytes) if the {@link file}.
     */
    public int64 filesize { get; private set; }

    protected Attachment(string id,
                         Mime.ContentType content_type,
                         string? content_id,
                         string? content_description,
                         Mime.ContentDisposition content_disposition,
                         string? content_filename,
                         File file,
                         int64 filesize) {
        this.id = id;
        this.content_type = content_type;
        this.content_id = content_id;
        this.content_description = content_description;
        this.content_disposition = content_disposition;
        this.content_filename = content_filename;
        this.file = file;
        this.filesize = filesize;
    }
}

