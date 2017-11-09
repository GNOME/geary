/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * The RFC 2342 NAMESPACE command.
 *
 * Determines the mailbox name prefix and hierarchy delimiter for the
 * personal, other user's and public namespaces.
 *
 * @see [[https://tools.ietf.org/html/rfc2342]]
 */
public class Geary.Imap.NamespaceCommand : Command {

    public const string NAME = "NAMESPACE";

    public NamespaceCommand() {
        base(NAME);
    }

}
