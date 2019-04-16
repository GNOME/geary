/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.Outbox.EmailIdentifier : Geary.EmailIdentifier {


    private const string VARIANT_TYPE = "(yxx)";

    public int64 message_id { get; private set; }
    public int64 ordering { get; private set; }


    public EmailIdentifier(int64 message_id, int64 ordering) {
        base("Outbox.EmailIdentifier:%s".printf(message_id.to_string()));
        this.message_id = message_id;
        this.ordering = ordering;
    }

    internal EmailIdentifier.from_variant(GLib.Variant serialised)
        throws EngineError.BAD_PARAMETERS {
        if (serialised.get_type_string() != VARIANT_TYPE) {
            throw new EngineError.BAD_PARAMETERS(
                "Invalid serialised id type: %s", serialised.get_type_string()
            );
        }
        GLib.Variant mid = serialised.get_child_value(1);
        GLib.Variant uid = serialised.get_child_value(2);
        this(mid.get_int64(), uid.get_int64());
    }

    public override int natural_sort_comparator(Geary.EmailIdentifier o) {
        EmailIdentifier? other = o as EmailIdentifier;
        if (other == null) {
            return 1;
        }
        return (int) (ordering - other.ordering).clamp(-1, 1);
    }

    public override GLib.Variant to_variant() {
        // Return a tuple to satisfy the API contract, add an 's' to
        // inform GenericAccount that it's an SMTP id.
        return new GLib.Variant.tuple(new Variant[] {
                new GLib.Variant.byte('s'),
                new GLib.Variant.int64(this.message_id),
                new GLib.Variant.int64(this.ordering)
            });
    }

}
