/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.ComposedEmail : BaseObject {
    public const string MAILTO_SCHEME = "mailto:";
    
    public const Geary.Email.Field REQUIRED_REPLY_FIELDS =
        Geary.Email.Field.HEADER
        | Geary.Email.Field.BODY
        | Geary.Email.Field.ORIGINATORS
        | Geary.Email.Field.RECEIVERS
        | Geary.Email.Field.REFERENCES
        | Geary.Email.Field.SUBJECT
        | Geary.Email.Field.DATE;
    
    public DateTime date { get; set; }
    public RFC822.MailboxAddresses from { get; set; }
    public RFC822.MailboxAddresses? to { get; set; default = null; }
    public RFC822.MailboxAddresses? cc { get; set; default = null; }
    public RFC822.MailboxAddresses? bcc { get; set; default = null; }
    public string? in_reply_to { get; set; default = null; }
    public Geary.Email? reply_to_email { get; set; default = null; }
    public string? references { get; set; default = null; }
    public string? subject { get; set; default = null; }
    public string? body_text { get; set; default = null; }
    public string? body_html { get; set; default = null; }
    public string? mailer { get; set; default = null; }
    public Gee.Set<File> attachment_files { get; private set;
        default = new Gee.HashSet<File>(Geary.Files.nullable_hash, Geary.Files.nullable_equal); }
    
    public ComposedEmail(DateTime date, RFC822.MailboxAddresses from, 
        RFC822.MailboxAddresses? to = null, RFC822.MailboxAddresses? cc = null,
        RFC822.MailboxAddresses? bcc = null, string? subject = null,
        string? body_text = null, string? body_html = null) {
        this.date = date;
        this.from = from;
        this.to = to;
        this.cc = cc;
        this.bcc = bcc;
        this.subject = subject;
        this.body_text = body_text;
        this.body_html = body_html;
    }
}

