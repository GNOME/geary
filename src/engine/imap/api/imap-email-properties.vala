/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.EmailProperties : Geary.EmailProperties, Gee.Hashable<Geary.Imap.EmailProperties> {


    public InternalDate? internaldate { get; private set; }
    public RFC822Size? rfc822_size { get; private set; }

    public EmailProperties(InternalDate internaldate,
                           RFC822Size rfc822_size) {
        base (internaldate.value, rfc822_size.value);
        this.internaldate = internaldate;
        this.rfc822_size = rfc822_size;
    }

    public bool equal_to(Geary.Imap.EmailProperties other) {
        if (this == other)
            return true;

        // for simplicity and robustness, internaldate and rfc822_size must be present in both
        // to be considered equal
        if (internaldate == null || other.internaldate == null)
            return false;

        if (rfc822_size == null || other.rfc822_size == null)
            return false;

        return true;
    }

    public uint hash() {
        return to_string().hash();
    }

    public override string to_string() {
        return "internaldate:%s/size:%s".printf((internaldate != null) ? internaldate.to_string() : "(none)",
            (rfc822_size != null) ? rfc822_size.to_string() : "(none)");
    }
}

