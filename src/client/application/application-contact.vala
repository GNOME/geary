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

    /** The avatar of the contact. */
    public GLib.LoadableIcon? avatar { get {
      if (this.individual != null)
        return this.individual.avatar;
      else
        return null;
    }}

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
    public bool load_remote_resources { get; private set; }

    /** The set of email addresses associated with this contact. */
    public Gee.Collection<Geary.RFC822.MailboxAddress> email_addresses {
        get {
            Gee.Collection<Geary.RFC822.MailboxAddress>? addrs =
                this._email_addresses;
            if (addrs == null) {
                addrs = new Gee.LinkedList<Geary.RFC822.MailboxAddress>();
                foreach (Folks.EmailFieldDetails email in
                         this.individual.email_addresses) {
                    addrs.add(new Geary.RFC822.MailboxAddress(
                                  this.display_name, email.value
                              ));
                }
                this._email_addresses = addrs;
            }
            return this._email_addresses;
        }
    }
    private Gee.Collection<Geary.RFC822.MailboxAddress>? _email_addresses = null;


    /** Fired when the contact has changed in some way. */
    public signal void changed();


    /** The Folks individual for the contact, if any. */
    internal Folks.Individual? individual { get; private set; }

    /** The Engine contact, if any. */
    private Geary.Contact? engine = null;

    private weak ContactStore store;


    private Contact(ContactStore store, Folks.Individual? source) {
        this.store = store;
        update_from_individual(source);
        update();
    }

    internal Contact.for_folks(ContactStore store,
                               Folks.Individual? source) {
        this(store, source);
    }

    internal Contact.for_engine(ContactStore store,
                                string display_name,
                                Geary.Contact source) {
        this(store, null);
        this.engine = source;
        this.engine.flags.added.connect(on_engine_flags_changed);
        this.engine.flags.removed.connect(on_engine_flags_changed);
        update_name(display_name);
        update_from_engine();
    }

    ~Contact() {
        // Disconnect from signals if any
        update_from_individual(null);
        if (this.engine != null) {
            this.engine.flags.added.disconnect(on_engine_flags_changed);
            this.engine.flags.removed.disconnect(on_engine_flags_changed);
        }
    }

    /**
     * Determines if this contact is equal to another.
     *
     * Returns true if the other contact has the same Folks
     * individual, engine contact, or if none of the above display
     * name.
     */
    public bool equal_to(Contact? other) {
        if (other == null) {
            return false;
        }
        if (this == other) {
            return true;
        }

        if (this.individual != null) {
            return (
                other.individual != null &&
                this.individual.id == other.individual.id
            );
        }

        if (this.display_name != other.display_name ||
            this.email_addresses.size != other.email_addresses.size) {
            return false;
        }

        foreach (Geary.RFC822.MailboxAddress this_addr in this.email_addresses) {
            bool found = false;
            foreach (Geary.RFC822.MailboxAddress other_addr
                     in other.email_addresses) {
                if (this_addr.equal_to(other_addr)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }

        return true;
    }

    /** Invokes the desktop contacts application to save this contact. */
    public async void save_to_desktop(GLib.Cancellable? cancellable)
        throws GLib.Error {
        Folks.Persona? persona = null;
        ContactStore? contacts = this.store;
        if (contacts != null) {
            Folks.PersonaStore? personas = contacts.individuals.primary_store;
            if (personas != null && personas.can_add_personas == TRUE) {
                GLib.HashTable<string,GLib.Value?> details =
                    new GLib.HashTable<string,GLib.Value?>(GLib.str_hash,
                                                           GLib.str_equal);

                GLib.Value name_value = GLib.Value(typeof(string));
                name_value.set_string(this.display_name);
                details.insert(
                    Folks.PersonaStore.detail_key(
                        Folks.PersonaDetail.FULL_NAME
                    ),
                    name_value
                );

                Gee.Set<Folks.EmailFieldDetails> email_addresses =
                    new Gee.HashSet<Folks.EmailFieldDetails>();
                GLib.Value email_value = GLib.Value(typeof(Gee.Set));
                foreach (Geary.RFC822.MailboxAddress addr
                         in this.email_addresses) {
                    email_addresses.add(
                        new Folks.EmailFieldDetails(addr.address)
                    );
                }
                email_value.set_object(email_addresses);
                details.insert(
                    Folks.PersonaStore.detail_key(
                        Folks.PersonaDetail.EMAIL_ADDRESSES
                    ),
                    email_value
                );

                persona = yield personas.add_persona_from_details(details);
            }
        }
        if (persona == null) {
            throw new Geary.EngineError.UNSUPPORTED(
                "Supported persona store not found"
            );
        }

        Folks.Individual? individual = persona.individual;
        if (individual == null) {
            throw new Geary.EngineError.UNSUPPORTED(
                "Individual not created for persona"
            );
        }

        update_from_individual(individual);
        update();
        changed();

        yield open_on_desktop(cancellable);

        // XXX Un-comment and use the section below instead of the
        // code above when something has been done about
        // https://gitlab.gnome.org/GNOME/gnome-contacts/merge_requests/66

        // GLib.DBusConnection dbus = yield GLib.Bus.get(
        // GLib.BusType.SESSION, cancellable ); GLib.DBusActionGroup
        // contacts = DBusActionGroup.get( dbus, "org.gnome.Contacts",
        // "/org/gnome/Contacts" );

        // GLib.Variant param = new GLib.Variant.array(
        //     new GLib.VariantType("(ss)"),
        //     new GLib.Variant[] {
        //         new GLib.Variant.tuple(
        //             new GLib.Variant[] {
        //                 Folks.PersonaStore.detail_key(
        //                     Folks.PersonaDetail.FULL_NAME
        //                 ),
        //                 this.display_name ?? ""
        //             }
        //         ),
        //         new GLib.Variant.tuple(
        //             new GLib.Variant[] {
        //                 Folks.PersonaStore.detail_key(
        //                     Folks.PersonaDetail.EMAIL_ADDRESSES
        //                 ),
        //                 this.contact.email
        //             }
        //         )
        //     }
        // );

        // contacts.activate_action("create-contact", param);
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
        if (store != null) {
            Gee.Collection<Geary.Contact> contacts =
                new Gee.LinkedList<Geary.Contact>();
            foreach (Geary.RFC822.MailboxAddress mailbox in this.email_addresses) {
                Geary.Contact? contact = yield store.lookup_engine_contact(
                    mailbox, cancellable
                );
                if (enabled) {
                    contact.flags.add(
                        Geary.Contact.Flags.ALWAYS_LOAD_REMOTE_IMAGES
                    );
                } else {
                    contact.flags.remove(
                        Geary.Contact.Flags.ALWAYS_LOAD_REMOTE_IMAGES
                    );
                }
                contacts.add(contact);
            }

            yield store.account.contact_store.update_contacts(
                contacts, cancellable
            );

            this.load_remote_resources = enabled;
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

    private void update_name(string name) {
        this.display_name = name;
        this.display_name_is_email =
            Geary.RFC822.MailboxAddress.is_valid_address(name);
    }

    private void on_individual_avatar_notify() {
        notify_property("avatar");
    }

    private void update_from_individual(Folks.Individual? replacement) {
        if (this.individual != null) {
            this.individual.notify["avatar"].disconnect(this.on_individual_avatar_notify);
            this.individual.notify.disconnect(this.on_individual_notify);
            this.individual.removed.disconnect(this.on_individual_removed);
        }

        this.individual = replacement;

        if (this.individual != null) {
            this.individual.notify["avatar"].connect(this.on_individual_avatar_notify);
            this.individual.notify.connect(this.on_individual_notify);
            this.individual.removed.connect(this.on_individual_removed);
        }
    }

    private void update_from_engine() {
        Geary.RFC822.MailboxAddress mailbox = this.engine.get_rfc822_address();
        this._email_addresses = Geary.Collection.single(mailbox);
        this.load_remote_resources = this.engine.flags.always_load_remote_images();
    }

    private void update() {
        if (this.individual != null) {
            update_name(this.individual.display_name);
            this.is_favourite = this.individual.is_favourite;
            this.is_trusted = (this.individual.trust_level == PERSONAS);
            this.is_desktop_contact = true;
            this.load_remote_resources = true;
        } else {
            this.is_favourite = false;
            this.is_trusted = false;
            this.is_desktop_contact = false;
            this.load_remote_resources = false;
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

        update_from_individual(replacement);
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

    private void on_engine_flags_changed() {
        update_from_engine();
    }

}
