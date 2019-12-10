/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.ImapDB.EmailIdentifier : Geary.EmailIdentifier {


    private const string VARIANT_TYPE = "(y(xx))";


    public int64 message_id { get; private set; }
    public Imap.UID? uid { get; private set; }

    public EmailIdentifier(int64 message_id, Imap.UID? uid) {
        assert(message_id != Db.INVALID_ROWID);

        this.message_id = message_id;
        this.uid = uid;
    }

    // Used when a new message comes off the wire and doesn't have a rowid associated with it (yet)
    // Requires a UID in order to find or create such an association
    public EmailIdentifier.no_message_id(Imap.UID uid) {
        message_id = Db.INVALID_ROWID;
        this.uid = uid;
    }

    /** Reconstructs an identifier from its variant representation. */
    public EmailIdentifier.from_variant(GLib.Variant serialised)
        throws EngineError.BAD_PARAMETERS {
        if (serialised.get_type_string() != VARIANT_TYPE) {
            throw new EngineError.BAD_PARAMETERS(
                "Invalid serialised id type: %s", serialised.get_type_string()
            );
        }
        GLib.Variant inner = serialised.get_child_value(1);
        Imap.UID? uid = null;
        int64 uid_value = inner.get_child_value(1).get_int64();
        if (uid_value >= 0) {
            uid = new Imap.UID(uid_value);
        }
        this(inner.get_child_value(0).get_int64(), uid);
    }

    // Used to promote an id created with no_message_id to one that has a
    // message id.  Warning: this causes the hash value to change, so if you
    // have any EmailIdentifiers in a hashed data structure, this will cause
    // you not to be able to find them.
    public void promote_with_message_id(int64 message_id) {
        assert(this.message_id == Db.INVALID_ROWID);
        this.message_id = message_id;
    }

    public bool has_uid() {
        return (uid != null) && uid.is_valid();
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

    public override int natural_sort_comparator(Geary.EmailIdentifier o) {
        ImapDB.EmailIdentifier? other = o as ImapDB.EmailIdentifier;
        if (other == null)
            return 1;

        if (uid == null)
            return 1;

        if (other.uid == null)
            return -1;

        return uid.compare_to(other.uid);
    }

    public override GLib.Variant to_variant() {
        // Return a tuple to satisfy the API contract, add an 'i' to
        // inform GenericAccount that it's an IMAP id.
        int64 uid_value = this.uid != null ? this.uid.value : -1;
        return new GLib.Variant.tuple(new Variant[] {
                new GLib.Variant.byte('i'),
                new GLib.Variant.tuple(new Variant[] {
                        new GLib.Variant.int64(this.message_id),
                        new GLib.Variant.int64(uid_value)
                    })
            });
    }

    public override string to_string() {
        return "%s(%lld,%s)".printf(
            this.get_type().name(),
            this.message_id,
            this.uid != null ? this.uid.to_string() : "null"
        );
    }

    public static Gee.Set<Imap.UID> to_uids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        Gee.HashSet<Imap.UID> uids = new Gee.HashSet<Imap.UID>();
        foreach (ImapDB.EmailIdentifier id in ids) {
            if (id.uid != null)
                uids.add(id.uid);
        }

        return uids;
    }

}
