/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Contact information for an individual.
 *
 * This class aggregates data from for both the Engine and Folks,
 * allowing contacts information for a specific mailbox to be
 * queried. Contacts are obtained from the {@link ContactStore} for an
 * account.
 */
public class Application.Contact {


    /** The human-readable name of the contact. */
    public string display_name { get; private set; }

    /** Determines if {@link display_name} is trusted by the user. */
    public bool display_name_is_trusted { get; private set; default = false; }

    /** Determines if {@link display_name} the same as its email address. */
    public bool display_name_is_email { get; private set; default = false; }

    /** Determines if email from this contact should load remote resources. */
    public bool load_remote_resources {
        get {
            return (
                this.contact != null &&
                this.contact.contact_flags.always_load_remote_images()
            );
        }
    }

    private weak ContactStore store;
    private Geary.Contact? contact;


    internal Contact(ContactStore store,
                     Geary.Contact? contact,
                     Geary.RFC822.MailboxAddress source) {
        this.store = store;
        this.contact = contact;

        if (contact != null) {
            this.display_name = contact.real_name;
        } else {
            this.display_name = source.name;
        }

        // Use the email address as the display name if the existing
        // display name looks in any way sketchy, regardless of where
        // it came from
        if (source.is_spoofed() ||
            Geary.String.is_empty_or_whitespace(this.display_name) ||
            Geary.RFC822.MailboxAddress.is_valid_address(this.display_name)) {
            this.display_name = source.address;
            this.display_name_is_email = true;
        }
    }

    /** Sets remote resource loading for this contact. */
    public async void set_remote_resource_loading(bool enabled,
                                                  GLib.Cancellable? cancellable)
        throws GLib.Error {
        ContactStore? store = this.store;
        if (store != null && this.contact != null) {
            Geary.ContactFlags flags = new Geary.ContactFlags();
            flags.add(Geary.ContactFlags.ALWAYS_LOAD_REMOTE_IMAGES);

            yield store.account.get_contact_store().mark_contacts_async(
                Geary.Collection.single(this.contact),
                enabled ? flags : null,
                !enabled ? flags : null //,
                // XXX cancellable
            );
        }
    }

    /** Returns a string representation for debugging */
    public string to_string() {
        return "Contact(\"%s\")".printf(this.display_name);
    }

}
