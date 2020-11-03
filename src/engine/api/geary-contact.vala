/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.Contact : BaseObject {


    /**
     * Standard values for contact importance..
     */
    public enum Importance {
        DESKTOP = 200,
        SENT_TO = 100,
        RECEIVED_FROM = 70,  // Equivalent to old TO_FROM value
        SEEN = 30 // Equivalent to old CC_TO value
    }

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
                ret += flag.serialise() + " ";
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


    /** Normalises an email address as for {@link normalized_email}. */
    public static string normalise_email(string address) {
        return address.normalize().casefold();
    }


    public string normalized_email { get; private set; }
    public string email { get; private set; }
    public string? real_name { get; set; }
    public int highest_importance { get; set; }
    public Flags flags { get; set; default = new Flags(); }

    public Contact(string email,
                   string? real_name,
                   int highest_importance,
                   string? normalized_email = null) {
        this.normalized_email = normalized_email ?? normalise_email(email);
        this.email = email;
        this.real_name = (
            (real_name != email && real_name != normalized_email)
            ? real_name : null
        );
        this.highest_importance = highest_importance;
    }

    public Contact.from_rfc822_address(RFC822.MailboxAddress address,
                                       int highest_importance) {
        this(
            address.address,
            address.has_distinct_name() ? address.name : null,
            highest_importance
        );
    }

    public RFC822.MailboxAddress get_rfc822_address() {
        return new RFC822.MailboxAddress(real_name, email);
    }

}
