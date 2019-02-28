/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an IMAP command tag.
 *
 * Tags are assigned by the client for each {@link Command} it sends to the server.  Tags have
 * a general form of <a-z><000-999>, although that's only by convention and is not required.
 *
 * Special tags exist, namely to indicated an untagged response and continuations.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-2.2.1]]
 */

public class Geary.Imap.Tag : AtomParameter, Gee.Hashable<Geary.Imap.Tag> {
    public const string UNTAGGED_VALUE = "*";
    public const string CONTINUATION_VALUE = "+";
    public const string UNASSIGNED_VALUE = "----";

    private static Tag? untagged = null;
    private static Tag? unassigned = null;
    private static Tag? continuation = null;

    public Tag(string ascii) {
        base (ascii);
    }

    public Tag.from_parameter(StringParameter strparam) {
        base (strparam.ascii);
    }

    internal static void init() {
        get_untagged();
        get_continuation();
        get_unassigned();
    }

    public static Tag get_untagged() {
        if (untagged == null)
            untagged = new Tag(UNTAGGED_VALUE);

        return untagged;
    }

    public static Tag get_continuation() {
        if (continuation == null)
            continuation = new Tag(CONTINUATION_VALUE);

        return continuation;
    }

    public static Tag get_unassigned() {
        if (unassigned == null)
            unassigned = new Tag(UNASSIGNED_VALUE);

        return unassigned;
    }

    /**
     * Returns true if the StringParameter resembles a tag token: an unquoted non-empty string
     * that either matches the untagged or continuation special tags or
     */
    public static bool is_tag(StringParameter stringp) {
        if (stringp is QuotedStringParameter)
            return false;

        if (stringp.is_empty())
            return false;

        if (stringp.equals_cs(UNTAGGED_VALUE) || stringp.equals_cs(CONTINUATION_VALUE))
            return true;

        int index = 0;
        for (;;) {
            char ch = stringp.ascii[index++];
            if (ch == String.EOS)
                break;

            if (DataFormat.is_tag_special(ch))
                return false;
        }

        return true;
    }

    public bool is_tagged() {
        return !equals_cs(UNTAGGED_VALUE) && !equals_cs(CONTINUATION_VALUE) && !equals_cs(UNASSIGNED_VALUE);
    }

    public bool is_continuation() {
        return equals_cs(CONTINUATION_VALUE);
    }

    public bool is_assigned() {
        return !equals_cs(UNASSIGNED_VALUE) && !equals_cs(CONTINUATION_VALUE);
    }

    public uint hash() {
        return Ascii.str_hash(ascii);
    }

    public bool equal_to(Geary.Imap.Tag tag) {
        if (this == tag)
            return true;

        return equals_cs(tag.ascii);
    }
}

