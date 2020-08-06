/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
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
    Gee.Hashable<MailboxAddresses>,
    DecodedMessageData {


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


    /**
     * Constructs a new mailbox list.
     *
     * If the optional collection of addresses is not given, the list
     * is created empty. Otherwise the collection's addresses are
     * added to the list by iterating over it in natural order.
     */
    public MailboxAddresses(Gee.Collection<MailboxAddress>? addrs = null) {
        if (addrs != null) {
            this.addrs.add_all(addrs);
        }
    }

    /** Constructs a new mailbox list with a single address. */
    public MailboxAddresses.single(MailboxAddress addr) {
        this.addrs.add(addr);
    }

    /** Constructs a new mailbox list by parsing a RFC822 string. */
    public MailboxAddresses.from_rfc822_string(string rfc822)
        throws Error {
        var list = GMime.InternetAddressList.parse(
            Geary.RFC822.get_parser_options(),
            rfc822
        );
        if (list == null) {
            throw new Error.INVALID("Not a RFC822 mailbox address list");
        }
        this.from_gmime(list);
    }

    /** Constructs a new mailbox from a GMime list. */
    public MailboxAddresses.from_gmime(GMime.InternetAddressList list)
        throws Error {
        int length = list.length();
        if (length == 0) {
            throw new Error.INVALID("No addresses in list");
        }
        for (int i = 0; i < length; i++) {
            var addr = list.get_address(i);
            var mbox_addr = addr as GMime.InternetAddressMailbox;
            if (mbox_addr != null) {
                this.addrs.add(new MailboxAddress.from_gmime(mbox_addr));
            } else {
                // XXX this is pretty bad - we just flatten the
                // group's addresses into this list, merging lists and
                // losing the group names.
                var mbox_group = addr as GMime.InternetAddressGroup;
                if (mbox_group != null) {
                    var group_list = mbox_group.get_members();
                    for (int j = 0; j < group_list.length(); j++) {
                        var group_addr =
                           group_list.get_address(j) as GMime.InternetAddressMailbox;
                        if (group_addr != null) {
                            this.addrs.add(
                                new MailboxAddress.from_gmime(group_addr)
                            );
                        }
                    }
                }
            }
        }
    }

    /** Returns the address at the given index, if it exists. */
    public new MailboxAddress? get(int index) {
        return this.addrs.get(index);
    }

    /** Returns a read-only iterator of the addresses in this list. */
    public Gee.Iterator<MailboxAddress> iterator() {
        return this.addrs.read_only_view.iterator();
    }

    /** Returns a read-only collection of the addresses in this list. */
    public Gee.List<MailboxAddress> get_all() {
        return this.addrs.read_only_view;
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
     * Returns a list with the given mailbox appended if not already present.
     *
     * This list is returned if the given mailbox is already present,
     * otherwise the result of a call to {@link concatenate_mailbox} is
     * returned.
     */
    public MailboxAddresses merge_mailbox(MailboxAddress other) {
        return (
            this.addrs.contains(other)
            ? this
            : this.concatenate_mailbox(other)
        );
    }

    /**
     * Returns a list with the given mailboxes appended if not already present.
     *
     * This list is returned if all given mailboxes are already
     * present, otherwise the result of a call to {@link
     * concatenate_mailbox} for each not present is returned.
     */
    public MailboxAddresses merge_list(MailboxAddresses other) {
        var list = this;
        foreach (var addr in other) {
            if (!this.addrs.contains(addr)) {
                list = list.concatenate_mailbox(addr);
            }
        }
        return list;
    }

    /**
     * Returns a new list with the given address appended to this list's.
     */
    public MailboxAddresses concatenate_mailbox(MailboxAddress other) {
        var new_addrs = new MailboxAddresses(this.addrs);
        new_addrs.addrs.add(other);
        return new_addrs;
    }

    /**
     * Returns a new list with the given addresses appended to this list's.
     */
    public MailboxAddresses concatenate_list(MailboxAddresses others) {
        var new_addrs = new MailboxAddresses(this.addrs);
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

    /** Determines if this list contains all of the other's, in any order. */
    public bool contains_all(MailboxAddresses other) {
        return (
            this == other ||
            (this.addrs.size == other.addrs.size &&
             this.addrs.contains_all(other.addrs))
        );
    }

    /** Determines if this list contains all of the other's, in order. */
    public bool equal_to(MailboxAddresses other) {
        if (this == other) {
            return true;
        }
        if (this.addrs.size != other.addrs.size) {
            return false;
        }
        for (int i = 0; i < this.addrs.size; i++) {
            if (!this.addrs[i].equal_to(other.addrs[i])) {
                return false;
            }
        }
        return true;
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
