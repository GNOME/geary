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
    public RFC822.MailboxAddresses? from { get { return this._from; } }
    private RFC822.MailboxAddresses? _from  = null;

    /** {@inheritDoc} */
    public RFC822.MailboxAddress? sender { get { return this._sender; } }
    private RFC822.MailboxAddress? _sender = null;

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? reply_to { get { return this._reply_to; } }
    private RFC822.MailboxAddresses? _reply_to = null;

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? to { get { return this._to; } }
    private RFC822.MailboxAddresses? _to = null;

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? cc { get { return this._cc; } }
    private RFC822.MailboxAddresses? _cc = null;

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? bcc { get { return this._bcc; } }
    private RFC822.MailboxAddresses? _bcc = null;

    /** {@inheritDoc} */
    public RFC822.MessageID? message_id { get { return this._message_id; } }
    private RFC822.MessageID? _message_id = null;

    /** {@inheritDoc} */
    public RFC822.MessageIDList? in_reply_to { get { return this._in_reply_to; } }
    private RFC822.MessageIDList? _in_reply_to = null;

    /** {@inheritDoc} */
    public RFC822.MessageIDList? references { get { return this._references; } }
    private RFC822.MessageIDList? _references = null;

    /** {@inheritDoc} */
    public RFC822.Subject? subject { get { return this._subject; } }
    private RFC822.Subject? _subject = null;

    /** {@inheritDoc} */
    public RFC822.Date? date { get { return this._date; } }
    private RFC822.Date? _date = null;

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

    public ComposedEmail(GLib.DateTime date, RFC822.MailboxAddresses from) {
        set_date(date);
        this._from = from;
    }

    public ComposedEmail set_date(GLib.DateTime date) {
        this._date = new RFC822.Date(date);
        return this;
    }

    public ComposedEmail set_sender(RFC822.MailboxAddress? sender) {
        this._sender = sender;
        return this;
    }

    public ComposedEmail set_to(RFC822.MailboxAddresses? recipients) {
        this._to = empty_to_null(recipients);
        return this;
    }

    public ComposedEmail set_cc(RFC822.MailboxAddresses? recipients) {
        this._cc = empty_to_null(recipients);
        return this;
    }

    public ComposedEmail set_bcc(RFC822.MailboxAddresses? recipients) {
        this._bcc = empty_to_null(recipients);
        return this;
    }

    public ComposedEmail set_reply_to(RFC822.MailboxAddresses? recipients) {
        this._reply_to = empty_to_null(recipients);
        return this;
    }

    public ComposedEmail set_message_id(RFC822.MessageID? id) {
        this._message_id = id;
        return this;
    }

    public ComposedEmail set_in_reply_to(RFC822.MessageIDList? messages) {
        this._in_reply_to = empty_to_null(messages);
        return this;
    }

    public ComposedEmail set_references(RFC822.MessageIDList? messages) {
        this._references = empty_to_null(messages);
        return this;
    }

    public ComposedEmail set_subject(string? subject) {
        this._subject = (
            String.is_empty_or_whitespace(subject)
            ? null
            : new RFC822.Subject(subject)
        );
        return this;
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

    private T empty_to_null<T>(T list) {
        T ret = list;
        RFC822.MailboxAddresses? addresses = list as RFC822.MailboxAddresses;
        if (addresses != null && addresses.size == 0) {
            ret = null;
        } else {
            RFC822.MessageIDList? ids = list as RFC822.MessageIDList;
            if (ids != null && ids.size == 0) {
                ret = null;
            }
        }
        return ret;
    }

}
