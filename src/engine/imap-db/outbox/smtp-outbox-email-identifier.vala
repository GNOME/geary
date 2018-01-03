/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.SmtpOutboxEmailIdentifier : Geary.EmailIdentifier {


    private const string VARIANT_TYPE = "(yxx)";

    public int64 message_id { get; private set; }
    public int64 ordering { get; private set; }


    public SmtpOutboxEmailIdentifier(int64 message_id, int64 ordering) {
        base ("SmtpOutboxEmailIdentifer:%s".printf(message_id.to_string()));
        this.message_id = message_id;
        this.ordering = ordering;
    }

    internal SmtpOutboxEmailIdentifier.from_variant(Variant serialised)
        throws EngineError {
        if (serialised.get_type_string() != VARIANT_TYPE) {
            throw new EngineError.BAD_PARAMETERS(
                "Invalid serialised id type: %s", serialised.get_type_string()
            );
        }
        Variant mid = serialised.get_child_value(1);
        Variant uid = serialised.get_child_value(2);
        this(mid.get_int64(), uid.get_int64());
    }

    public override int natural_sort_comparator(Geary.EmailIdentifier o) {
        SmtpOutboxEmailIdentifier? other = o as SmtpOutboxEmailIdentifier;
        if (other == null)
            return 1;

        return (int) (ordering - other.ordering).clamp(-1, 1);
    }

    public override Variant to_variant() {
        // Return a tuple to satisfy the API contract, add an 's' to
        // inform GenericAccount that it's an SMTP id.
        return new Variant.tuple(new Variant[] {
                new Variant.byte('s'),
                new Variant.int64(this.message_id),
                new Variant.int64(this.ordering)
            });
    }

}
