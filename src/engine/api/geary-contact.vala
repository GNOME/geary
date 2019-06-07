/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Contact : BaseObject {


    /**
     * Named flags for contact objects.
     */
    public class Flags : Geary.NamedFlags {

        public static NamedFlag ALWAYS_LOAD_REMOTE_IMAGES {
            get {
                if (_always_load_remote_images == null) {
                    _always_load_remote_images = new NamedFlag("ALWAYSLOADREMOTEIMAGES");
                }

                return _always_load_remote_images;
            }
        }
        private static NamedFlag? _always_load_remote_images = null;


        public bool always_load_remote_images() {
            return contains(ALWAYS_LOAD_REMOTE_IMAGES);
        }

        public string serialize() {
            string ret = "";
            foreach (NamedFlag flag in list) {
                ret += flag.serialize() + " ";
            }

            return ret.strip();
        }

        public void deserialize(string? flags) {
            if (!String.is_empty(flags)) {
                foreach (string flag in flags.split(" ")) {
                    add(new NamedFlag(flag));
                }
            }
        }

    }


    public string normalized_email { get; private set; }
    public string email { get; private set; }
    public string? real_name { get; private set; }
    public int highest_importance { get; set; }
    public Flags flags { get; set; default = new Flags(); }

    public Contact(string email,
                   string? real_name,
                   int highest_importance,
                   string? normalized_email = null) {
        this.normalized_email = normalized_email ?? email.normalize().casefold();
        this.email = email;
        this.real_name = real_name;
        this.highest_importance = highest_importance;
    }

    public Contact.from_rfc822_address(RFC822.MailboxAddress address,
                                       int highest_importance) {
        this(address.address, address.name, highest_importance);
    }

    public RFC822.MailboxAddress get_rfc822_address() {
        return new RFC822.MailboxAddress(real_name, email);
    }

}
