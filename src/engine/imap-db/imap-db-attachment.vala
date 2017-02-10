/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.Attachment : Geary.Attachment {
    public const Email.Field REQUIRED_FIELDS = Email.REQUIRED_FOR_MESSAGE;

    internal const string NULL_FILE_NAME = "none";
    private const string ATTACHMENTS_DIR = "attachments";

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

    public static File generate_file(File data_dir, int64 message_id, int64 attachment_id,
        string? filename) {
        return get_attachments_dir(data_dir)
            .get_child(message_id.to_string())
            .get_child(attachment_id.to_string())
            .get_child(filename ?? NULL_FILE_NAME);
    }

    public static File get_attachments_dir(File data_dir) {
        return data_dir.get_child(ATTACHMENTS_DIR);
    }
}
