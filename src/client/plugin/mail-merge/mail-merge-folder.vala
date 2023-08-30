/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Plugin to Fill in and send email templates using a spreadsheet.
 */
public class MailMerge.Folder : Geary.AbstractLocalFolder {


    private class EmailIdentifier : Geary.EmailIdentifier {


        private const string VARIANT_TYPE = "(y(x))";

        public int64 message_id { get; private set; }


        public EmailIdentifier(int64 message_id) {
            this.message_id = message_id;
        }

        internal EmailIdentifier.from_variant(GLib.Variant serialised)
            throws Geary.EngineError.BAD_PARAMETERS {
            if (serialised.get_type_string() != VARIANT_TYPE) {
                throw new Geary.EngineError.BAD_PARAMETERS(
                    "Invalid serialised id type: %s", serialised.get_type_string()
                );
            }
            GLib.Variant inner = serialised.get_child_value(1);
            GLib.Variant mid = inner.get_child_value(0);
            this(mid.get_int64());
        }

        /** {@inheritDoc} */
        public override uint hash() {
            return GLib.int64_hash(this.message_id);
        }

        /** {@inheritDoc} */
        public override bool equal_to(Geary.EmailIdentifier other) {
            return (
                this.get_type() == other.get_type() &&
                this.message_id == ((EmailIdentifier) other).message_id
            );
        }

        /** {@inheritDoc} */
        public override string to_string() {
            return "%s(%lld)".printf(this.get_type().name(), this.message_id);
        }

        public override int natural_sort_comparator(Geary.EmailIdentifier o) {
            EmailIdentifier? other = o as EmailIdentifier;
            if (other == null) {
                return 1;
            }
            return (int) (this.message_id - other.message_id).clamp(-1, 1);
        }

        public override GLib.Variant to_variant() {
            return new GLib.Variant.tuple(new Variant[] {
                    new GLib.Variant.byte('m'),
                    new GLib.Variant.tuple(new Variant[] {
                            new GLib.Variant.int64(this.message_id),
                        })
                });
        }

    }


    private class FolderProperties : Geary.FolderProperties {

        public FolderProperties() {
            base(
                0, 0,
                Geary.Trillian.FALSE, Geary.Trillian.FALSE, Geary.Trillian.TRUE,
                true, false, false
            );
        }

        public void set_total(int total) {
            this.email_total = total;
        }

    }


    /** {@inheritDoc} */
    public override Geary.Account account {
        get { return this._account; }
    }
    private Geary.Account _account;

    /** {@inheritDoc} */
    public override Geary.FolderProperties properties {
        get { return _properties; }
    }
    private FolderProperties _properties = new FolderProperties();

    /** {@inheritDoc} */
    public override Geary.FolderPath path {
        get { return _path; }
    }
    private Geary.FolderPath _path;

    /** {@inheritDoc} */
    public override Geary.Folder.SpecialUse used_as {
        get { return this._used_as; }
    }
    Geary.Folder.SpecialUse _used_as = NONE;

    /** The source data file used the folder. */
    public GLib.File data_location { get; private set; }

    /** The display name for {@link data_location}. */
    public string data_display_name { get; private set; }

    /** The number of email that have been sent. */
    public uint email_sent { get; private set; default = 0; }

    /** The number of email in total. */
    public uint email_total { get; private set; default = 0; }

    /** Specifies if the merged mail is currently being sent. */
    public bool is_sending { get; private set; default = false; }


    private Gee.List<Geary.EmailIdentifier> ids =
        new Gee.ArrayList<Geary.EmailIdentifier>();
    private Gee.Map<Geary.EmailIdentifier,Geary.ComposedEmail> composed =
        new Gee.HashMap<Geary.EmailIdentifier,Geary.ComposedEmail>();
    private Gee.Map<Geary.EmailIdentifier,Geary.Email> email =
        new Gee.HashMap<Geary.EmailIdentifier,Geary.Email>();
    private Geary.Email template;
    private Csv.Reader data;
    private GLib.Cancellable loading = new GLib.Cancellable();
    private GLib.Cancellable sending = new GLib.Cancellable();


    /** Emitted when an error sending an email is reported. */
    public signal void send_error(GLib.Error error);


    public async Folder(Geary.Account account,
                        Geary.FolderRoot root,
                        Geary.Email template,
                        GLib.File data_location,
                        Csv.Reader data)
        throws GLib.Error {
        this._account = account;
        this._path = root.get_child("$Plugin.MailMerge$");
        this.template = template;
        this.data_location = data_location;
        this.data = data;

        var info = yield data_location.query_info_async(
            GLib.FileAttribute.STANDARD_DISPLAY_NAME,
            NONE,
            GLib.Priority.DEFAULT,
            null
        );
        this.data_display_name = info.get_display_name();

        // Do this in the background to avoid blocking while the whole
        // file is processed
        this.load_data.begin(this.loading);
    }


    /** Starts or stops the folder sending mail. */
    public void set_sending(bool is_sending) {
        if (is_sending && !this.is_sending) {
            this.send_loop.begin();
            this.is_sending = true;
        } else if (!is_sending && this.is_sending) {
            this.sending.cancel();
            this.sending = new GLib.Cancellable();
        }
    }

    /** {@inheritDoc} */
    public override async bool close_async(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        var is_closing = yield base.close_async(cancellable);
        if (is_closing) {
            this.loading.cancel();
            set_sending(false);
        }
        return is_closing;
    }

    /** {@inheritDoc} */
    public override async Gee.Collection<Geary.EmailIdentifier> contains_identifiers(
        Gee.Collection<Geary.EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        return Geary.traverse(
            ids
        ).filter(
            (id) => this.email.has_key(id)
        ).to_hash_set();
    }

    public override async Geary.Email
        fetch_email_async(Geary.EmailIdentifier id,
                          Geary.Email.Field required_fields,
                          Geary.Folder.ListFlags flags,
                          GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_open();
        var email = this.email.get(id);
        if (email == null) {
            throw new Geary.EngineError.NOT_FOUND(
                "No email with ID %s in merge", id.to_string()
            );
        }
        return email;
    }

    public override async Gee.List<Geary.Email>?
        list_email_by_id_async(Geary.EmailIdentifier? initial_id,
                               int count,
                               Geary.Email.Field required_fields,
                               Geary.Folder.ListFlags flags,
                               GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_open();

        var initial = initial_id as EmailIdentifier;
        if (initial_id != null && initial == null) {
            throw new Geary.EngineError.BAD_PARAMETERS(
                "EmailIdentifier %s not from merge",
                initial_id.to_string()
            );
        }

        Gee.List<Geary.Email> list = new Gee.ArrayList<Geary.Email>();
        if (!this.ids.is_empty && count > 0) {
            int incr = 1;
            if (Geary.Folder.ListFlags.OLDEST_TO_NEWEST in flags) {
                incr = -1;
            }
            int next_index = -1;
            if (initial == null) {
                initial = (EmailIdentifier) (
                    incr > 0
                    ? this.ids.first()
                    : this.ids.last()
                );
                next_index = (int) initial.message_id;
            } else {
                if (Geary.Folder.ListFlags.INCLUDING_ID in flags) {
                    list.add(this.email.get(this.ids[(int) initial.message_id]));
                }
                next_index = (int) initial.message_id;
                next_index += incr;
            }

            while (list.size < count &&
                   next_index >= 0 &&
                   next_index < this.ids.size) {
                list.add(this.email.get(this.ids[next_index]));
                next_index += incr;
            }
        }

        return (list.size > 0) ? list : null;
    }

    public override async Gee.List<Geary.Email>?
        list_email_by_sparse_id_async(Gee.Collection<Geary.EmailIdentifier> ids,
                                      Geary.Email.Field required_fields,
                                      Geary.Folder.ListFlags flags,
                                      GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_open();
        Gee.List<Geary.Email> list = new Gee.ArrayList<Geary.Email>();
        foreach (var id in ids) {
            var email = this.email.get(id);
            if (email == null) {
                throw new Geary.EngineError.NOT_FOUND(
                    "No email with ID %s in merge", id.to_string()
                );
            }
            list.add(email);
        }
        return (list.size > 0) ? list : null;
    }

    public override void set_used_as_custom(bool enabled)
        throws Geary.EngineError.UNSUPPORTED {
        this._used_as = (
            enabled
            ? Geary.Folder.SpecialUse.CUSTOM
            : Geary.Folder.SpecialUse.NONE
        );
    }


    // NB: This is called from a thread outside of the main loop
    private async void load_data(GLib.Cancellable? cancellable) {
        int64 next_id = 0;
        try {
            var template = yield load_template(cancellable);
            Geary.Memory.Buffer? raw_rfc822 = null;
            yield Geary.Nonblocking.Concurrent.global.schedule_async(
                (c) => {
                    raw_rfc822 = template.get_message().get_rfc822_buffer();
                },
                cancellable
            );

            string[] headers = yield this.data.read_record();
            var fields = new Gee.HashMap<string,string>();
            string[] record = yield this.data.read_record();
            while (record != null) {
                fields.clear();
                for (int i = 0; i < headers.length; i++) {
                    fields.set(headers[i], record[i]);
                }
                var processor = new Processor(this.template);
                var composed = processor.merge(fields);
                var message = yield new Geary.RFC822.Message.from_composed_email(
                    composed, null, GMime.EncodingConstraint.7BIT, cancellable
                );

                var id = new EmailIdentifier(next_id++);
                var email = new Geary.Email.from_message(id, message);
                // Don't set a date since it would be re-set on send,
                // and we don't want to give people the wrong idea of
                // what it will be
                email.set_send_date(null);
                email.set_flags(new Geary.EmailFlags());

                // Update folder state then notify about the new email
                this.ids.add(id);
                this.composed.set(id, composed);
                this.email.set(id, email);
                this._properties.set_total((int) next_id);
                this.email_total = (uint) next_id;

                notify_email_inserted(Geary.Collection.single(id));
                record = yield this.data.read_record();
            }
        } catch (GLib.Error err) {
            debug("Error processing email for merge: %s", err.message);
        }
    }

    private async Geary.Email load_template(GLib.Cancellable? cancellable)
        throws GLib.Error {
        var template = this.template;
        if (!template.fields.fulfills(Geary.Email.REQUIRED_FOR_MESSAGE)) {
            template = yield this.account.local_fetch_email_async(
                template.id,
                Geary.Email.REQUIRED_FOR_MESSAGE,
                cancellable
            );
        }
        return template;
    }

    private async void send_loop() {
        var cancellable = this.sending;
        var smtp = this._account.outgoing as Geary.Smtp.ClientService;
        if (smtp != null) {
            while (!this.ids.is_empty && !this.sending.is_cancelled()) {
                var last = this.ids.size - 1;
                var id = this.ids[last];

                try {
                    var composed = this.composed.get(id);
                    composed.set_date(new GLib.DateTime.now());
                    yield smtp.send_email(composed, cancellable);

                    this.email_sent++;

                    this.ids.remove_at(last);
                    this.email.unset(id);
                    this.composed.unset(id);
                    this._properties.set_total(last);
                    notify_email_removed(Geary.Collection.single(id));

                    // Rate limit to ~30/minute for now
                    GLib.Timeout.add_seconds(2, this.send_loop.callback);
                    yield;
                } catch (GLib.Error err) {
                    warning("Error sending merge email: %s", err.message);
                    send_error(err);
                    break;
                }
            }
        } else {
            warning("Account has no outgoing SMTP service");
        }
        this.is_sending = false;
    }

}
