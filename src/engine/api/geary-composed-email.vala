/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Encapsulates a message created by the user in the composer.
 */
public class Geary.ComposedEmail : EmailHeaderSet, BaseObject {

    private const string IMG_SRC_TEMPLATE = "src=\"%s\"";

    public const Geary.Email.Field REQUIRED_REPLY_FIELDS = (
        Geary.Email.Field.HEADER
        | Geary.Email.Field.BODY
        | Geary.Email.Field.ORIGINATORS
        | Geary.Email.Field.RECEIVERS
        | Geary.Email.Field.REFERENCES
        | Geary.Email.Field.SUBJECT
        | Geary.Email.Field.DATE
    );

    /** {@inheritDoc} */
    public RFC822.Date? date { get; protected set; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? from { get; protected set; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddress? sender { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? to { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? cc { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? bcc { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? reply_to { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MessageID? message_id { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MessageIDList? in_reply_to { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MessageIDList? references { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.Subject? subject { get; protected set; default = null; }

    public string? body_text { get; set; default = null; }
    public string? body_html { get; set; default = null; }
    public string? mailer { get; set; default = null; }

    public Geary.Email? reply_to_email { get; set; default = null; }

    public Gee.Set<File> attached_files { get; private set;
        default = new Gee.HashSet<File>(Geary.Files.nullable_hash, Geary.Files.nullable_equal); }
    public Gee.Map<string,Memory.Buffer> inline_files { get; private set;
        default = new Gee.HashMap<string,Memory.Buffer>(); }
    public Gee.Map<string,Memory.Buffer> cid_files { get; private set;
        default = new Gee.HashMap<string,Memory.Buffer>(); }

    public string img_src_prefix { get; set; default = ""; }

    public ComposedEmail(DateTime date, RFC822.MailboxAddresses from) {
        this.date = new RFC822.Date.from_date_time(date);
        this.from = from;
    }

    public ComposedEmail set_sender(RFC822.MailboxAddress? sender) {
        this.sender = sender;
        return this;
    }

    public ComposedEmail set_to(RFC822.MailboxAddresses? recipients) {
        this.to = recipients;
        return this;
    }

    public ComposedEmail set_cc(RFC822.MailboxAddresses? recipients) {
        this.cc = recipients;
        return this;
    }

    public ComposedEmail set_bcc(RFC822.MailboxAddresses? recipients) {
        this.bcc = recipients;
        return this;
    }

    public ComposedEmail set_reply_to(RFC822.MailboxAddresses? recipients) {
        this.reply_to = recipients;
        return this;
    }

    public ComposedEmail set_message_id(RFC822.MessageID? id) {
        this.message_id = id;
        return this;
    }

    public ComposedEmail set_in_reply_to(RFC822.MessageIDList? messages) {
        this.in_reply_to = messages;
        return this;
    }

    public ComposedEmail set_references(RFC822.MessageIDList? messages) {
        this.references = messages;
        return this;
    }

    public ComposedEmail set_subject(string? subject) {
        this.subject = (
            String.is_empty_or_whitespace(subject)
            ? null
            : new RFC822.Subject(subject)
        );
        return this;
    }

    public async Geary.RFC822.Message to_rfc822_message(string? message_id,
                                                        GLib.Cancellable? cancellable) {
        return yield new RFC822.Message.from_composed_email(
            this, message_id, cancellable
        );
    }

    /**
     * Determines if an IMG SRC value is present in the HTML part.
     *
     * Returns true if `value` is present as an IMG SRC value.
     */
    public bool contains_inline_img_src(string value) {
        // XXX This and replace_inline_img_src are pretty
        // hacky. Should probably be working with a DOM tree.
        return this.body_html.contains(IMG_SRC_TEMPLATE.printf(value));
    }

    /**
     * Replaces matching IMG SRC values in the HTML part.
     *
     * Will also remove the random prefix set by the composer for
     * security reasons.
     *
     * Returns true if `orig` has been replaced by `replacement`.
     */
    public bool replace_inline_img_src(string orig, string replacement) {
        // XXX This and contains_inline_img_src are pretty
        // hacky. Should probably be working with a DOM tree.
        int index = -1;
        if (this.body_html != null) {
            string prefixed_orig = IMG_SRC_TEMPLATE.printf(this.img_src_prefix + orig);
            index = this.body_html.index_of(prefixed_orig);
            if (index != -1) {
                this.body_html = this.body_html.substring(0, index) +
                     IMG_SRC_TEMPLATE.printf(replacement) +
                     this.body_html.substring(index + prefixed_orig.length);
            }
        }
        return index != -1;
    }

}
