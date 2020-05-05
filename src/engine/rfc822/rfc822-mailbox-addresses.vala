/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An immutable representation an RFC 822 address list.
 *
 * This would typically be found as the value of the To, CC, BCC and
 * other headers fields.
 *
 * See [[https://tools.ietf.org/html/rfc5322#section-3.4]]
 */
public class Geary.RFC822.MailboxAddresses :
    Geary.MessageData.AbstractMessageData,
    Geary.MessageData.SearchableMessageData,
    Geary.RFC822.MessageData, Gee.Hashable<MailboxAddresses> {


    /**
     * Converts a list of mailbox addresses to a string.
     *
     * The delegate //to_s// is used for converting addresses in the
     * given list. If the list is empty, the given empty string is
     * returned.
     */
    private static string list_to_string(Gee.List<MailboxAddress> addrs,
                                          ListToStringDelegate to_s) {
        switch (addrs.size) {
            case 0:
                return "";

            case 1:
                return to_s(addrs[0]);

            default:
                StringBuilder builder = new StringBuilder();
                foreach (MailboxAddress addr in addrs) {
                    if (!String.is_empty(builder.str))
                        builder.append(", ");

                    builder.append(to_s(addr));
                }

                return builder.str;
        }
    }


    /** Signature for "to_string" implementation for {@link list_to_string}. */
    private delegate string ListToStringDelegate(MailboxAddress address);

    /** Returns the number of addresses in this list. */
    public int size {
        get { return this.addrs.size; }
    }

    /** Determines if there are no addresses in the list. */
    public bool is_empty {
        get { return this.addrs.is_empty; }
    }

    private Gee.List<MailboxAddress> addrs = new Gee.ArrayList<MailboxAddress>();

    private bool hash_cached = false;
    private uint hash_value = 0;


    public MailboxAddresses(Gee.Collection<MailboxAddress>? addrs = null) {
        if (addrs != null) {
            this.addrs.add_all(addrs);
        }
    }

    public MailboxAddresses.single(MailboxAddress addr) {
        this.addrs.add(addr);
    }

    public MailboxAddresses.from_rfc822_string(string rfc822)
        throws RFC822Error {
        var addrlist = GMime.InternetAddressList.parse(null, rfc822);
        if (addrlist == null) {
            throw new RFC822Error.INVALID("Not a RFC822 mailbox address list");
        }

        int length = addrlist.length();
        for (int ctr = 0; ctr < length; ctr++) {
            GMime.InternetAddress? addr = addrlist.get_address(ctr);

            GMime.InternetAddressMailbox? mbox_addr = addr as GMime.InternetAddressMailbox;
            if (mbox_addr != null) {
                this.addrs.add(new MailboxAddress.gmime(mbox_addr));
            } else {
                // XXX this is pretty bad - we just flatten the
                // group's addresses into this list, merging lists and
                // losing the group names.
                GMime.InternetAddressGroup? mbox_group = addr as GMime.InternetAddressGroup;
                if (mbox_group != null) {
                    GMime.InternetAddressList group_list = mbox_group.get_members();
                    for (int i = 0; i < group_list.length(); i++) {
                        GMime.InternetAddressMailbox? group_addr =
                            addrlist.get_address(i) as GMime.InternetAddressMailbox;
                        if (group_addr != null) {
                            this.addrs.add(new MailboxAddress.gmime(group_addr));
                        }
                    }
                }
            }
        }
    }

    public new MailboxAddress? get(int index) {
        return addrs.get(index);
    }

    public Gee.Iterator<MailboxAddress> iterator() {
        return addrs.iterator();
    }

    public Gee.List<MailboxAddress> get_all() {
        return addrs.read_only_view;
    }

    public bool contains_normalized(string address) {
        if (addrs.size < 1)
            return false;

        string normalized_address = address.normalize().casefold();

        foreach (MailboxAddress mailbox_address in addrs) {
            if (mailbox_address.address.normalize().casefold() == normalized_address)
                return true;
        }

        return false;
    }

    public bool contains(string address) {
        if (addrs.size < 1)
            return false;

        foreach (MailboxAddress a in addrs)
            if (a.address == address)
                return true;

        return false;
    }

    /**
     * Returns a new list with the given addresses appended to this list's.
     */
    public MailboxAddresses append(MailboxAddresses others) {
        MailboxAddresses new_addrs = new MailboxAddresses(this.addrs);
        new_addrs.addrs.add_all(others.addrs);
        return new_addrs;
    }

    /**
     * Returns the addresses suitable for display to a human.
     *
     * @return a string containing each message in the list,
     * serialised by a call to {@link MailboxAddress.to_full_display}
     * for each, separated by commas.
     */
    public string to_full_display() {
        return list_to_string(addrs, (a) => a.to_full_display());
    }

    /**
     * Returns the addresses suitable for insertion into an RFC822 message.
     *
     * RFC822 quoting is performed if required.
     *
     * @see MailboxAddress.to_rfc822_string
     */
    public string to_rfc822_string() {
        return list_to_string(addrs, (a) => a.to_rfc822_string());
    }

    public uint hash() {
        if (!this.hash_cached) {
            // Sort the addresses to ensure a stable hash
            var sorted_addresses = traverse<RFC822.MailboxAddress>(addrs)
                .map<string>(m => m.address)
                .to_sorted_list(String.stri_cmp);

            // xor all strings in sorted order
            uint xor = 0;
            foreach (string address in sorted_addresses) {
                xor ^= address.hash();
            }
            this.hash_value = xor;
            this.hash_cached = true;
        }

        return this.hash_value;
    }

    public bool equal_to(MailboxAddresses other) {
        return (
            this == other ||
            (this.addrs.size == other.addrs.size &&
             this.addrs.contains_all(other.addrs))
        );
    }

    /**
     * See Geary.MessageData.SearchableMessageData.
     */
    public string to_searchable_string() {
        return list_to_string(addrs, (a) => a.to_searchable_string());
    }

    public override string to_string() {
        return this.size > 0
            ? list_to_string(addrs, (a) => a.to_string())
            : "(no addresses)";
    }

}
