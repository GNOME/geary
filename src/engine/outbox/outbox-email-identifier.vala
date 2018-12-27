/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.Outbox.EmailIdentifier : Geary.EmailIdentifier {


    public int64 ordering { get; private set; }


    public EmailIdentifier(int64 message_id, int64 ordering) {
        base("Outbox.EmailIdentifier:%s".printf(message_id.to_string()));
        this.ordering = ordering;
    }

    public override int natural_sort_comparator(Geary.EmailIdentifier o) {
        EmailIdentifier? other = o as EmailIdentifier;
        if (other == null) {
            return 1;
        }
        return (int) (ordering - other.ordering).clamp(-1, 1);
    }

}
