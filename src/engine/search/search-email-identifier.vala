/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.Search.EmailIdentifier :
    Geary.EmailIdentifier, Gee.Comparable<EmailIdentifier> {


    private const string VARIANT_TYPE = "(y(vx))";


    public static int compare_descending(EmailIdentifier a, EmailIdentifier b) {
        return b.compare_to(a);
    }

    public static Gee.Collection<Geary.EmailIdentifier> to_source_ids(
        Gee.Collection<Geary.EmailIdentifier> ids
    ) {
        var engine_ids = new Gee.LinkedList<Geary.EmailIdentifier>();
        foreach (var id in ids) {
            var search_id = id as EmailIdentifier;
            engine_ids.add(search_id.source_id ?? id);
        }
        return engine_ids;
    }

    public static Geary.EmailIdentifier to_source_id(
        Geary.EmailIdentifier id
    ) {
        var search_id = id as EmailIdentifier;
        return search_id.source_id ?? id;
    }


    public Geary.EmailIdentifier source_id { get; private set; }

    public GLib.DateTime? date_received { get; private set; }


    public EmailIdentifier(Geary.EmailIdentifier source_id,
                           GLib.DateTime? date_received) {
        this.source_id = source_id;
        this.date_received = date_received;
    }

    /** Reconstructs an identifier from its variant representation. */
    public EmailIdentifier.from_variant(GLib.Variant serialised,
                                        Account account)
        throws EngineError.BAD_PARAMETERS {
        if (serialised.get_type_string() != VARIANT_TYPE) {
            throw new EngineError.BAD_PARAMETERS(
                "Invalid serialised id type: %s", serialised.get_type_string()
            );
        }
        GLib.Variant inner = serialised.get_child_value(1);
        this(
            account.to_email_identifier(
                inner.get_child_value(0).get_variant()
            ),
            new GLib.DateTime.from_unix_utc(
                inner.get_child_value(1).get_int64()
            )
        );
    }

    /** {@inheritDoc} */
    public override uint hash() {
        return this.source_id.hash();
    }

    /** {@inheritDoc} */
    public override bool equal_to(Geary.EmailIdentifier other) {
        return (
            this.get_type() == other.get_type() &&
            this.source_id.equal_to(((EmailIdentifier) other).source_id)
        );
    }

    /** {@inheritDoc} */
    public override GLib.Variant to_variant() {
        // Return a tuple to satisfy the API contract, add an 's' to
        // inform GenericAccount that it's an IMAP id.
        return new GLib.Variant.tuple(new Variant[] {
                new GLib.Variant.byte('s'),
                new GLib.Variant.tuple(new Variant[] {
                        new GLib.Variant.variant(this.source_id.to_variant()),
                        new GLib.Variant.int64(this.date_received.to_unix())
                    })
            });
    }

    /** {@inheritDoc} */
    public override string to_string() {
        return "%s(%s,%lld)".printf(
            this.get_type().name(),
            this.source_id.to_string(),
            this.date_received.to_unix()
        );
    }

    public override int natural_sort_comparator(Geary.EmailIdentifier o) {
        EmailIdentifier? other = o as EmailIdentifier;
        if (other == null)
            return 1;

        return compare_to(other);
    }

    public virtual int compare_to(EmailIdentifier other) {
        // if both have date received, compare on that, using stable sort if the same
        if (date_received != null && other.date_received != null) {
            int compare = date_received.compare(other.date_received);

            return (compare != 0) ? compare : stable_sort_comparator(other);
        }

        // if neither have date received, fall back on stable sort
        if (date_received == null && other.date_received == null)
            return stable_sort_comparator(other);

        // put identifiers with no date ahead of those with
        return (date_received == null ? -1 : 1);
    }

}
