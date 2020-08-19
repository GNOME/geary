/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * Collects application state related to a single open account.
 */
public class Application.AccountContext : Geary.BaseObject {

    /** The account for this context. */
    public Geary.Account account { get; private set; }

    /** The account's Inbox folder */
    public Geary.Folder? inbox = null;

    /** The account's search folder */
    public Geary.App.SearchFolder search = null;

    /** The account's email store */
    public Geary.App.EmailStore emails { get; private set; }

    /** The account's contact store */
    public ContactStore contacts { get; private set; }

    /** The account's application command stack. */
    public CommandStack commands {
        get { return this.controller_stack; }
    }

    /** A cancellable tied to the life-cycle of the account. */
    public Cancellable cancellable {
        get; private set; default = new Cancellable();
    }

    /** The account's application command stack. */
    internal ControllerCommandStack controller_stack {
        get; protected set; default = new ControllerCommandStack();
    }

    /** Determines if the account has an authentication problem. */
    internal bool authentication_failed {
        get; internal set; default = false;
    }

    /** Determines if the account is prompting for a password. */
    internal bool authentication_prompting {
        get; internal set; default = false;
    }

    /** Determines if currently prompting for a password. */
    internal uint authentication_attempts {
        get; internal set; default = 0;
    }

    /** Determines if any TLS certificate errors have been seen. */
    internal bool tls_validation_failed {
        get; internal set; default = false;
    }

    /** Determines if currently prompting about TLS certificate errors. */
    internal bool tls_validation_prompting {
        get; internal set; default = false;
    }

    private Gee.Map<Geary.FolderPath,FolderContext> folders =
        new Gee.HashMap<Geary.FolderPath,FolderContext>();


    /** Emitted when folders contexts become available. */
    public signal void folders_available(Gee.Collection<FolderContext> available);

    /** Emitted when folders contexts become available. */
    public signal void folders_unavailable(Gee.Collection<FolderContext> unavailable);


    public AccountContext(Geary.Account account,
                          Geary.App.SearchFolder search,
                          Geary.App.EmailStore emails,
                          Application.ContactStore contacts) {
        this.account = account;
        this.search = search;
        this.emails = emails;
        this.contacts = contacts;
    }

    /** Returns the current effective status for the account. */
    public Geary.Account.Status get_effective_status() {
        Geary.Account.Status current = this.account.current_status;
        Geary.Account.Status effective = 0;
        if (current.is_online()) {
            effective |= ONLINE;
        }
        if (current.has_service_problem()) {
            // Only retain service problem if the problem isn't auth
            // or cert related, that is handled elsewhere.
            const Geary.ClientService.Status SPECIALS[] = {
                AUTHENTICATION_FAILED,
                TLS_VALIDATION_FAILED
            };
            if (!(account.incoming.current_status in SPECIALS) &&
                !(account.outgoing.current_status in SPECIALS)) {
                effective |= SERVICE_PROBLEM;
            }
        }
        return effective;
    }

    /**
     * Returns read-only collection of all known folder contexts.
     */
    public Gee.Collection<FolderContext> get_folders() {
        return this.folders.values.read_only_view;
    }

    /**
     * Returns context for a folder belonging to this context's account.
     */
    public FolderContext? get_folder(Geary.Folder target) {
        FolderContext? context = null;
        if (this.account == target.account) {
            context = this.folders.get(target.path);
        }
        return context;
    }

    /** Adds a context for a folder belonging to the account. */
    public void add_folders(Gee.Collection<FolderContext> to_add) {
        foreach (var context in to_add) {
            this.folders.set(context.folder.path, context);
        }
        folders_available(to_add);
    }

    /** Adds a context for a folder belonging to the account. */
    public void remove_folders(Gee.Collection<FolderContext> to_remove) {
        foreach (var context in to_remove) {
            this.folders.unset(context.folder.path);
        }
        folders_unavailable(to_remove);
    }

}
