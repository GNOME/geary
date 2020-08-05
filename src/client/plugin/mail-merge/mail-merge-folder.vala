/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Plugin to Fill in and send email templates using a spreadsheet.
 */
public class Plugin.MailMergeFolder : Geary.AbstractLocalFolder {


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

    /**
     * {@inheritDoc}
     *
     * This is always {@link Folder.SpecialUse.CUSTOM}
     */
    public override Geary.Folder.SpecialUse used_as {
        get { return CUSTOM; }
    }

    private Gee.Map<Geary.EmailIdentifier,Geary.Email> map =
        new Gee.HashMap<Geary.EmailIdentifier,Geary.Email>();
    private Gee.List<Geary.Email> list =
        new Gee.ArrayList<Geary.Email>();
    private Geary.Email template;
    private Util.Csv.Reader data;
    private GLib.Cancellable loading = new GLib.Cancellable();


    public MailMergeFolder(Geary.Account account,
                           Geary.FolderRoot root,
                           Geary.Email template,
                           Util.Csv.Reader data) {
        this._account = account;
        this._path = root.get_child("$Plugin.MailMerge$");
        this.template = template;
        this.data = data;

        Geary.Nonblocking.Concurrent.global.schedule_async.begin(
            (c) => this.load_data(c),
            this.loading
        );
    }

    /** {@inheritDoc} */
    public override async Gee.Collection<Geary.EmailIdentifier> contains_identifiers(
        Gee.Collection<Geary.EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        return Geary.traverse(
            ids
        ).filter(
            (id) => this.map.has_key(id)
        ).to_hash_set();
    }

    public override async Geary.Email
        fetch_email_async(Geary.EmailIdentifier id,
                          Geary.Email.Field required_fields,
                          Geary.Folder.ListFlags flags,
                          GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_open();
        var email = this.map.get(id);
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
        if (!this.list.is_empty && count > 0) {
            int incr = 1;
            if (Geary.Folder.ListFlags.OLDEST_TO_NEWEST in flags) {
                incr = -1;
            }
            if (initial == null) {
                initial = (EmailIdentifier) (
                    incr > 0
                    ? this.list.first().id
                    : this.list.last().id
                );
            }

            int64 index = initial.message_id;
            if (Geary.Folder.ListFlags.INCLUDING_ID in flags) {
                list.add(this.list[(int) initial.message_id]);
            }
            index += incr;

            while (list.size < count && index > 0 && index < this.list.size) {
                list.add(this.list[(int) index]);
                index += incr;
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
            var email = this.map.get(id);
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
        throw new Geary.EngineError.UNSUPPORTED(
            "Folder special use cannot be changed"
        );
    }


    // NB: This is called from a thread outside of the main loop
    private void load_data(GLib.Cancellable? cancellable) {
        int64 next_id = 0;
        int loaded = 0;

        
    }

}
