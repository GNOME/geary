/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.RFC822.MailboxAddresses : Geary.MessageData.AbstractMessageData, 
    Geary.MessageData.SearchableMessageData, Geary.RFC822.MessageData, Gee.Hashable<MailboxAddresses> {
    
    public int size { get { return addrs.size; } }
    
    private Gee.List<MailboxAddress> addrs = new Gee.ArrayList<MailboxAddress>();
    
    public MailboxAddresses(Gee.Collection<MailboxAddress> addrs) {
        this.addrs.add_all(addrs);
    }
    
    public MailboxAddresses.single(MailboxAddress addr) {
        addrs.add(addr);
    }
    
    public MailboxAddresses.from_rfc822_string(string rfc822) {
        InternetAddressList addrlist = InternetAddressList.parse_string(rfc822);
        if (addrlist == null)
            return;

        int length = addrlist.length();
        for (int ctr = 0; ctr < length; ctr++) {
            InternetAddress? addr = addrlist.get_address(ctr);
            
            // TODO: Handle group lists
            InternetAddressMailbox? mbox_addr = addr as InternetAddressMailbox;
            if (mbox_addr == null)
                continue;
            
            addrs.add(new MailboxAddress(mbox_addr.get_name(), mbox_addr.get_addr()));
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
     * Returns the addresses suitable for insertion into an RFC822 message.  RFC822 quoting is
     * performed if required.
     *
     * @see RFC822.to_rfc822_string
     */
    public string to_rfc822_string() {
        return MailboxAddress.list_to_string(addrs, "", (a) => a.to_rfc822_string());
    }
    
    public uint hash() {
        // create sorted set to ensure ordering no matter the list's order
        Gee.TreeSet<string> sorted_addresses = traverse<RFC822.MailboxAddress>(addrs)
            .map<string>(m => m.address)
            .to_tree_set(String.stri_cmp);
        
        // xor all strings in sorted order
        uint xor = 0;
        foreach (string address in sorted_addresses)
            xor ^= address.hash();
        
        return xor;
    }
    
    public bool equal_to(MailboxAddresses other) {
        if (this == other)
            return true;
        
        if (addrs.size != other.addrs.size)
            return false;
        
        Gee.HashSet<RFC822.MailboxAddress> first = new Gee.HashSet<RFC822.MailboxAddress>();
        first.add_all(addrs);
        
        Gee.HashSet<RFC822.MailboxAddress> second = new Gee.HashSet<RFC822.MailboxAddress>();
        second.add_all(other.addrs);
        
        return Collection.are_sets_equal<RFC822.MailboxAddress>(first, second);
    }
    
    /**
     * See Geary.MessageData.SearchableMessageData.
     */
    public string to_searchable_string() {
        return MailboxAddress.list_to_string(addrs, "", (a) => a.to_searchable_string());
    }
    
    public override string to_string() {
        return MailboxAddress.list_to_string(addrs, "(no addresses)", (a) => a.to_string());
    }
}

