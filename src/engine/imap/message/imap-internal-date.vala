/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representations of IMAP's INTERNALDATE field.
 *
 * INTERNALDATE's format is
 *
 * dd-Mon-yyyy hh:mm:ss +hhmm
 *
 * Note that Mon is the standard ''English'' three-letter abbreviation.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-2.3.3]]
 */

public class Geary.Imap.InternalDate : Geary.MessageData.AbstractMessageData, Geary.Imap.MessageData,
    Gee.Hashable<InternalDate>, Gee.Comparable<InternalDate> {
    // see get_en_us_mon() for explanation
    private const string[] EN_US_MON = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    };

    private const string[] EN_US_MON_DOWN = {
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
    };

    public DateTime value { get; private set; }
    public string? original { get; private set; default = null; }

    private InternalDate(string original, DateTime datetime) {
        this.original = original;
        value = datetime;
    }

    public InternalDate.from_date_time(DateTime datetime) throws ImapError {
        value = datetime;
    }

    public static InternalDate decode(string internaldate) throws ImapError {
        if (String.is_empty(internaldate))
            throw new ImapError.PARSE_ERROR("Invalid INTERNALDATE: empty string");

        if (internaldate.length > 64)
            throw new ImapError.PARSE_ERROR("Invalid INTERNALDATE: too long (%d)", internaldate.length);

        // Alas, GMime.utils_header_decode_date() is too forgiving for our needs, so do it manually
        int day, year, hour, min, sec;
        char mon[4] = { 0 };
        char tz[6] = { 0 };
        int count = internaldate.scanf("%d-%3s-%d %d:%d:%d %5s", out day, mon, out year, out hour,
            out min, out sec, tz);
        if (count != 6 && count != 7)
            throw new ImapError.PARSE_ERROR("Invalid INTERNALDATE \"%s\": too few fields (%d)", internaldate, count);

        // check numerical ranges; this does not verify this is an actual date, DateTime will do
        // that (and round upward, which has to be accepted)
        if (!Numeric.int_in_range_inclusive(day, 1, 31)
            || !Numeric.int_in_range_inclusive(hour, 0, 23)
            || !Numeric.int_in_range_inclusive(min, 0, 59)
            || !Numeric.int_in_range_inclusive(sec, 0, 59)
            || year < 1970) {
            throw new ImapError.PARSE_ERROR("Invalid INTERNALDATE \"%s\": bad numerical range", internaldate);
        }

        // check month (this catches localization problems)
        int month = -1;
        string mon_down = Ascii.strdown(((string) mon));
        for (int ctr = 0; ctr < EN_US_MON_DOWN.length; ctr++) {
            if (mon_down == EN_US_MON_DOWN[ctr]) {
                month = ctr;

                break;
            }
        }

        if (month < 0)
            throw new ImapError.PARSE_ERROR("Invalid INTERNALDATE \"%s\": bad month", internaldate);

        GLib.TimeZone? timezone = null;
        if (tz[0] != '\0') {
            string tz_string = (string) tz;
            try {
                timezone = new GLib.TimeZone.identifier(tz_string);
            } catch (GLib.Error err) {
                warning("Invalid INTERNALDATE timezone \"%s\", %s", tz_string, err.message);
            }
        }
        if (timezone == null) {
            // If no timezone listed, ISO 8601 says to use local time.
            timezone = new GLib.TimeZone.local();
        }

        // assemble into DateTime, which validates the time as well
        // (this is why we want to keep original around, for other
        // reasons) ... month is 1-based in DateTime
        var datetime = new GLib.DateTime(
            timezone, year, month + 1, day, hour, min, sec
        );

        return new InternalDate(internaldate, datetime);
    }

    /**
     * Returns the {@link InternalDate} as a {@link Parameter}.
     */
    public Parameter to_parameter() {
        return Parameter.get_for_string(serialize());
    }

    /**
     * Returns the {@link InternalDate} as a {@link Parameter} for a {@link SearchCriterion}.
     *
     * @see serialize_for_search
     */
    public Parameter to_search_parameter() {
        return Parameter.get_for_string(serialize_for_search());
    }

    /**
     * Returns the {@link InternalDate}'s string representation.
     *
     * @see serialize_for_search
     */
    public string serialize() {
        return original ?? value.format("%d-%%s-%Y %H:%M:%S %z").printf(get_en_us_mon());
    }

    /**
     * Returns the {@link InternalDate}'s string representation for a SEARCH command.
     *
     * SEARCH does not respect time or timezone, so drop when sending it.  See
     * [[http://tools.ietf.org/html/rfc3501#section-6.4.4]]
     *
     * @see serialize
     * @see SearchCommand
     */
    public string serialize_for_search() {
        return value.format("%d-%%s-%Y").printf(get_en_us_mon());
    }

    /**
     * Because IMAP's INTERNALDATE strings are ''never'' localized (as best as I can gather), so
     * need to use en_US appreviated month names, as that's the only value in INTERNALDATE that is
     * in a language and not a numeric value.
     */
    private string get_en_us_mon() {
        // month is 1-based inside of DateTime
        int mon = (value.get_month() - 1).clamp(0, EN_US_MON.length - 1);

        return EN_US_MON[mon];
    }

    public uint hash() {
        return value.hash();
    }

    public bool equal_to(InternalDate other) {
        return value.equal(other.value);
    }

    public int compare_to(InternalDate other) {
        return value.compare(other.value);
    }

    public override string to_string() {
        return serialize();
    }
}

