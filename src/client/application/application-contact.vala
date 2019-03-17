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
public class Application.Contact : Geary.BaseObject {


    /** The human-readable name of the contact. */
    public string display_name { get; private set; }

    /** Determines if {@link display_name} the same as its email address. */
    public bool display_name_is_email { get; private set; default = false; }

    /** Determines if this contact was loaded from Folks. */
    public bool is_desktop_contact { get; private set; default = false; }

    /**
     * Determines if this contact is trusted.
     *
     * Contacts loaded from Folks that are trusted are trusted, all
     * other contacts are not.
     */
    public bool is_trusted { get; private set; default = false; }

    /**
     * Determines if this contact has been marked as a favourite.
     */
    public bool is_favourite { get; private set; default = false; }

    /**
     * Determines if email from this contact should load remote resources.
     *
     * Will automatically load resources from contacts in the desktop
     * database, or if the Engine's contact has been flagged to do so.
     */
    public bool load_remote_resources {
        get {
            return (
                this.individual != null ||
                (this.contact != null &&
                 this.contact.always_load_remote_images())
            );
        }
    }


    /** Fired when the contact has changed in some way. */
    public signal void changed();


    /** The Folks individual for the contact, if any. */
    internal Folks.Individual? individual { get; private set; }

    private weak ContactStore store;
    private Geary.Contact? contact;


    internal Contact(ContactStore store,
                     Folks.Individual? individual,
                     Geary.Contact? contact,
                     Geary.RFC822.MailboxAddress source) {
        this.store = store;
        this.contact = contact;
        update_individual(individual);

        update();
        if (Geary.String.is_empty_or_whitespace(this.display_name)) {
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

    ~Contact() {
        // Disconnect from signals if any
        update_individual(null);
    }

    /** Invokes the desktop contacts application to save this contact. */
    public async void save_to_desktop(GLib.Cancellable? cancellable)
        throws GLib.Error {
        GLib.DBusConnection dbus = yield GLib.Bus.get(
            GLib.BusType.SESSION, cancellable
        );
        GLib.DBusActionGroup contacts = DBusActionGroup.get(
            dbus, "org.gnome.Contacts", "/org/gnome/Contacts"
        );

        GLib.Variant param = new GLib.Variant.array(
            new GLib.VariantType("(ss)"),
            new GLib.Variant[] {
                new GLib.Variant.tuple(
                    new GLib.Variant[] {
                        Folks.PersonaStore.detail_key(
                            Folks.PersonaDetail.FULL_NAME
                        ),
                        this.display_name ?? ""
                    }
                ),
                new GLib.Variant.tuple(
                    new GLib.Variant[] {
                        Folks.PersonaStore.detail_key(
                            Folks.PersonaDetail.EMAIL_ADDRESSES
                        ),
                        this.contact.email
                    }
                )
            }
        );

        contacts.activate_action("create-contact", param);
    }

    /** Invokes the desktop contacts application to open this contact. */
    public async void open_on_desktop(GLib.Cancellable? cancellable)
        throws GLib.Error {
        GLib.DBusConnection dbus = yield GLib.Bus.get(
            GLib.BusType.SESSION, cancellable
        );
        GLib.DBusActionGroup contacts = DBusActionGroup.get(
            dbus, "org.gnome.Contacts", "/org/gnome/Contacts"
        );

        contacts.activate_action(
            "show-contact",
            new GLib.Variant.string(this.individual.id)
        );
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

        changed();
    }

    /** Sets remote resource loading for this contact. */
    public async void set_favourite(bool is_favourite,
                                    GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield this.individual.change_is_favourite(is_favourite);
    }

    /** Returns a string representation for debugging */
    public string to_string() {
        return "Contact(\"%s\")".printf(this.display_name);
    }

    private void update_individual(Folks.Individual? replacement) {
        if (this.individual != null) {
            this.individual.notify.disconnect(this.on_individual_notify);
            this.individual.removed.disconnect(this.on_individual_removed);
        }

        this.individual = replacement;

        if (this.individual != null) {
            this.individual.notify.connect(this.on_individual_notify);
            this.individual.removed.connect(this.on_individual_removed);
        }
    }

    private void update() {
        if (this.individual != null) {
            this.display_name = this.individual.display_name;
            this.is_favourite = this.individual.is_favourite;
            this.is_trusted = (this.individual.trust_level == PERSONAS);
            this.is_desktop_contact = true;
        } else {
            if (this.contact != null) {
                this.display_name = this.contact.real_name;
            }
            this.is_favourite = false;
            this.is_trusted = false;
            this.is_desktop_contact = false;
        }
    }

    private async void update_replacement(Folks.Individual? replacement) {
        if (replacement == null) {
            ContactStore? store = this.store;
            if (store != null) {
                try {
                    replacement = yield store.individuals.look_up_individual(
                        this.individual.id
                    );
                } catch (GLib.Error err) {
                    debug("Error loading replacement for Folks %s: %s",
                          this.individual.id, err.message);
                }
            }
        }

        update_individual(replacement);
        update();
        changed();
    }

    private void on_individual_notify() {
        update();
        changed();
    }

    private void on_individual_removed(Folks.Individual? replacement) {
        this.update_replacement.begin(replacement);
    }

}
