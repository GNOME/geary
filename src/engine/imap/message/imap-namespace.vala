/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Namespace component in a response for a NAMESPACE command.
 *
 * @see Geary.Imap.NamespaceCommand
 */
public class Geary.Imap.Namespace : BaseObject {


    public string prefix { get; private set; }
    public string? delim { get; private set; }


    public Namespace(string prefix, string? delim) {
        this.prefix = prefix;
        this.delim = delim;
    }

    public string to_string() {
        return "(%s,%s)".printf(this.prefix, this.delim ?? "NIL");
    }

}
