/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace GMime {
    public class InternetAddress {
        [CCode (cname="internet_address_get_name")]
        public unowned string get_name();
        [CCode (cname="internet_address_set_name")]
        public void set_name(string name);
        [CCode (cname="internet_address_to_string")]
        public virtual string to_string(bool encoded);
    }
    
    public class InternetAddressGroup {
        [CCode (cname="internet_address_group_new")]
        public InternetAddressGroup(string name);
        [CCode (cname="internet_address_group_get_members")]
        public InternetAddressList get_members();
        [CCode (cname="internet_address_group_set_members")]
        public void set_members(InternetAddressList members);
        [CCode (cname="internet_address_group_add_member")]
        public int add_member(InternetAddress member);
    }
    
    public class InternetAddressMailbox {
        [CCode (cname="internet_address_mailbox_new")]
        public InternetAddressMailbox(string name, string addr);
        [CCode (cname="internet_address_mailbox_get_addr")]
        public string get_addr();
        [CCode (cname="internet_address_mailbox_set_addr")]
        public void set_addr(string addr);
    }
    
    public class InternetAddressList {
        [CCode (cname="internet_address_list_new")]
        public InternetAddressList();
        [CCode (cname="internet_address_list_length")]
        public int length();
        [CCode (cname="internet_address_list_clear")]
        public void clear();
        [CCode (cname="internet_address_list_add")]
        public int add(InternetAddress addr);
        [CCode (cname="internet_address_list_insert")]
        public void insert(int index, InternetAddress addr);
        [CCode (cname="internet_address_list_remove")]
        public bool remove(InternetAddress addr);
        [CCode (cname="internet_address_list_remove_at")]
        public bool remove_at(int index);
        [CCode (cname="internet_address_list_contains")]
        public bool contains(InternetAddress addr);
        [CCode (cname="internet_address_list_index_of")]
        public int index_of(InternetAddress addr);
        [CCode (cname="internet_address_list_get_address")]
        public InternetAddress get_address(int index);
        [CCode (cname="internet_address_list_set_address")]
        public void set_address(int index, InternetAddress addr);
        [CCode (cname="internet_address_list_prepend")]
        public void prepend(InternetAddressList prepend);
        [CCode (cname="internet_address_list_append")]
        public void append(InternetAddressList append);
        [CCode (cname="internet_address_list_to_string")]
        public string to_string(bool encode);
        [CCode (cname="internet_address_list_parse_string")]
        public static InternetAddressList parse_string(string str);
    }
}

