/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A Folder represents the basic unit of organization for email.
 *
 * Each {@link Account} provides a hierarchical listing of Folders.
 * Note that while most folders are able to store email messages, some
 * folders may not and may exist purely to group together folders
 * below it in the account's folder hierarchy. Folders that can
 * contain email messages either store these messages purely locally
 * (for example, in the case of an ''outbox'' for mail queued for
 * sending), or as a representation of those found in a mailbox on a
 * remote mail server, such as those provided by an IMAP server. Email
 * messages are represented by the {@link Email} class, and many
 * folder methods will return collections of these.
 *
 * Folders that represent a remote folder extend {@link
 * RemoteFolder}. These cache the remote folder's email locally, and
 * the set of cached messages may be a subset of those available in
 * the mailbox, depending on an account's settings. Email messages may
 * be partially cached, in the case of a new message having just
 * arrived or a message with many large attachments that was not
 * completely downloaded.
 *
 * This class only offers a small selection of guaranteed
 * functionality (in particular, the ability to list its {@link
 * Email}).  Additional functionality for Folders is indicated by the
 * presence of {@link FolderSupport} interfaces, include {@link
 * FolderSupport.Remove}, {@link FolderSupport.Copy}, and so forth.
 */
public interface Geary.Folder : GLib.Object, Logging.Source {


    /**
     * A generic structure for representing and maintaining folder paths.
     *
     * A Path may have one parent and one child.  A Path without a parent is called a
     * root folder can be be created with {@link Root}, which is a Path.
     *
     * @see Root
     */
    public class Path :
        BaseObject, Gee.Hashable<Path>, Gee.Comparable<Path> {


        /** Type of the GLib.Variant used to represent folder paths */
        public const string VARIANT_TYPE = "(sas)";


        // Workaround for Vala issue #659. See children below.
        private class PathWeakRef {

            GLib.WeakRef weak_ref;

            public PathWeakRef(Path path) {
                this.weak_ref = GLib.WeakRef(path);
            }

            public Path? get() {
                return this.weak_ref.get() as Path;
            }

        }


        /** The base name of this folder, excluding parents. */
        public string name { get; private set; }

        /** The number of children under the root in this path. */
        public uint length {
            get {
                uint length = 0;
                Path parent = this.parent;
                while (parent != null) {
                    length++;
                    parent = parent.parent;
                }
                return length;
            }
        }

        /**
         * Whether this path is lexiographically case-sensitive.
         *
         * This has implications, as {@link Path} is Comparable and Hashable.
         */
        public bool case_sensitive { get; private set; }

        /** Determines if this path is a root folder path. */
        public bool is_root {
            get { return this.parent == null; }
        }

        /** Determines if this path is a child of the root folder. */
        public bool is_top_level {
            get {
                Path? parent = parent;
                return parent != null && parent.is_root;
            }
        }

        /** Returns the parent of this path. */
        public Path? parent { get; private set; }

        private string[] path;

        // Would use a `weak Path` value type for this map instead of
        // the custom class, but we can't currently reassign built-in
        // weak refs back to a strong ref at the moment, nor use a
        // GLib.WeakRef as a generics param. See Vala issue #659.
        private Gee.Map<string,PathWeakRef?> children =
        new Gee.HashMap<string,PathWeakRef?>();

        private uint? stored_hash = null;


        /** Constructor only for use by {@link Root}. */
        internal Path() {
            this.name = "";
            this.parent = null;
            this.case_sensitive = false;
            this.path = new string[0];
        }

        private Path.child(Path parent,
                                 string name,
                                 bool case_sensitive) {
            this.parent = parent;
            this.name = name;
            this.case_sensitive = case_sensitive;
            this.path = parent.path.copy();
            this.path += name;
        }

        /**
         * Returns the {@link Root} of this path.
         */
        public Root get_root() {
            Path? path = this;
            while (path.parent != null) {
                path = path.parent;
            }
            return (Root) path;
        }

        /**
         * Returns an array of the names of non-root elements in the path.
         */
        public string[] as_array() {
            return this.path;
        }

        /**
         * Creates a path that is a child of this folder.
         *
         * Specifying {@link Trillian.TRUE} or {@link Trillian.FALSE} for
         * `is_case_sensitive` forces case-sensitivity either way. If
         * {@link Trillian.UNKNOWN}, then {@link
         * Root.default_case_sensitivity} is used.
         */
        public virtual Path
        get_child(string name,
                  Trillian is_case_sensitive = Trillian.UNKNOWN) {
            Path? child = null;
            PathWeakRef? child_ref = this.children.get(name);
            if (child_ref != null) {
                child = child_ref.get();
            }
            if (child == null) {
                child = new Path.child(
                    this,
                    name,
                    is_case_sensitive.to_boolean(
                        get_root().default_case_sensitivity
                    )
                );
                this.children.set(name, new PathWeakRef(child));
            }
            return child;
        }

        /**
         * Determines if this path is a strict ancestor of another.
         */
        public bool is_descendant(Path target) {
            bool is_descendent = false;
            Path? path = target.parent;
            while (path != null) {
                if (path.equal_to(this)) {
                    is_descendent = true;
                    break;
                }
                path = path.parent;
            }
            return is_descendent;
        }

        /**
         * Does a Unicode-normalized, case insensitive match.  Useful for
         * getting a rough idea if a folder matches a name, but shouldn't
         * be used to determine strict equality.
         */
        public int compare_normalized_ci(Path other) {
            return compare_internal(other, false, true);
        }

        /**
         * {@inheritDoc}
         *
         * Comparisons for Path is defined as (a) empty paths
         * are less-than non-empty paths and (b) each element is compared
         * to the corresponding path element of the other Path
         * following collation rules for casefolded (case-insensitive)
         * compared, and (c) shorter paths are less-than longer paths,
         * assuming the path elements are equal up to the shorter path's
         * length.
         *
         * Note that {@link Path.case_sensitive} affects comparisons.
         *
         * Returns -1 if this path is lexiographically before the other, 1
         * if its after, and 0 if they are equal.
         */
        public int compare_to(Path other) {
            return compare_internal(other, true, false);
        }

        /**
         * {@inheritDoc}
         *
         * Note that {@link Path.case_sensitive} affects comparisons.
         */
        public uint hash() {
            if (this.stored_hash == null) {
                this.stored_hash = 0;
                Path? path = this;
                while (path != null) {
                    this.stored_hash ^= (case_sensitive)
                    ? str_hash(path.name) : str_hash(path.name.down());
                    path = path.parent;
                }
            }
            return this.stored_hash;
        }

        /** {@inheritDoc} */
        public bool equal_to(Path other) {
            return this.compare_internal(other, true, false) == 0;
        }

        /**
         * Returns a representation useful for serialisation.
         *
         * This can be used to transmit folder paths as D-Bus method and
         * GLib Action parameters, and so on.
         *
         * @return a serialised form of this path, that will match the
         * GVariantType specified by {@link VARIANT_TYPE}.
         * @see Root.from_variant
         */
        public GLib.Variant to_variant() {
            return new GLib.Variant.tuple(new GLib.Variant[] {
                    get_root().label,
                    as_array()
                });
        }

        /**
         * Returns a representation useful for debugging.
         *
         * Do not use this for obtaining an IMAP mailbox name to send to a
         * server, use {@link
         * Geary.Imap.MailboxSpecifier.MailboxSpecifier.from_folder_path}
         * instead. This method is useful for debugging and logging only.
         */
        public string to_string() {
            const char SEP = '>';
            StringBuilder builder = new StringBuilder();
            if (this.is_root) {
                builder.append_c(SEP);
            } else {
                foreach (string name in this.path) {
                    builder.append_c(SEP);
                    builder.append(name);
                }
            }
            return builder.str;
        }

        private int compare_internal(Path other,
                                     bool allow_case_sensitive,
                                     bool normalize) {
            if (this == other) {
                return 0;
            }

            int a_len = (int) this.length;
            int b_len = (int) other.length;
            if (a_len != b_len) {
                return a_len - b_len;
            }

            return compare_names(this, other, allow_case_sensitive, normalize);
        }

        private static int compare_names(Path a, Path b,
                                         bool allow_case_sensitive,
                                         bool normalize) {
            int cmp = 0;
            if (a.parent == null && b.parent == null) {
                cmp = strcmp(((Root) a).label, ((Root) b).label);
            } else {
                cmp = compare_names(
                    a.parent, b.parent, allow_case_sensitive, normalize
                );
            }

            if (cmp == 0) {
                string a_name = a.name;
                string b_name = b.name;

                if (normalize) {
                    a_name = a_name.normalize();
                    b_name = b_name.normalize();
                }

                if (!allow_case_sensitive
                    // if either case-sensitive, then comparison is CS
                    || (!a.case_sensitive && !b.case_sensitive)) {
                    a_name = a_name.casefold();
                    b_name = b_name.casefold();
                }

                return strcmp(a_name, b_name);
            }
            return cmp;
        }

    }


    /**
     * The root of a folder hierarchy.
     *
     * A {@link Path} can only be created by starting with a
     * Root and adding children via {@link Path.get_child}.
     * Because all Paths hold references to their parents, this
     * element can be retrieved with {@link Path.get_root}.
     */
    public class Root : Path {


        /**
         * A label for a folder root.
         *
         * Since there may be multiple folder roots (for example, local
         * and remote folders, or for different remote namespaces), the
         * label can be used to look up a specific root.
         */
        public string label { get; private set; }

        /**
         * The default case sensitivity of descendant folders.
         *
         * @see Path.get_child
         */
        public bool default_case_sensitivity { get; private set; }


        /**
         * Constructs a new folder root with given default sensitivity.
         */
        public Root(string label, bool default_case_sensitivity) {
            base();
            this.label = label;
            this.default_case_sensitivity = default_case_sensitivity;
        }

        /**
         * Copies a folder path using this as the root.
         *
         * This method can be used to simply copy a path, or change the
         * root that a path is attached to.
         */
        public Path copy(Path original) {
            Path copy = this;
            foreach (string step in original.as_array()) {
                copy = copy.get_child(step);
            }
            return copy;
        }

        /**
         * Reconstructs a path under this root from a GLib variant.
         *
         * @see Path.to_variant
         * @throws EngineError.BAD_PARAMETERS when the variant is not the
         * have the correct type or if the given root label does not match
         * this root's label.
         */
        public Path from_variant(GLib.Variant serialised)
        throws EngineError.BAD_PARAMETERS {
            if (serialised.get_type_string() != VARIANT_TYPE) {
                throw new EngineError.BAD_PARAMETERS(
                    "Invalid serialised id type: %s", serialised.get_type_string()
                );
            }

            string label = (string) serialised.get_child_value(0);
            if (this.label != label) {
                throw new EngineError.BAD_PARAMETERS(
                    "Invalid serialised folder root label: %s", label
                );
            }

            Path path = this;
            foreach (string step in serialised.get_child_value(1).get_strv()) {
                path = path.get_child(step);
            }
            return path;
        }

    }


    /**
     * Specifies the use of a specific folder.
     *
     * These are populated from a number of sources, including mailbox
     * names, protocol hints, and special folder implementations.
     */
    public enum SpecialUse {

        /** No special type, likely user-created. */
        NONE,

        // Well-known concrete folders

        /** Denotes the inbox for the account. */
        INBOX,

        /** Stores email to be kept. */
        ARCHIVE,

        /** Stores email that has not yet been sent. */
        DRAFTS,

        /** Stores spam, malware and other kinds of unwanted email. */
        JUNK,

        /** Stores email that is waiting to be sent. */
        OUTBOX,

        /** Stores email that has been sent. */
        SENT,

        /** Stores email that is to be deleted. */
        TRASH,

        // Virtual folders

        /** A view of all email in an account. */
        ALL_MAIL,

        /** A view of all flagged/starred email in an account. */
        FLAGGED,

        /** A view of email the server thinks is important. */
        IMPORTANT,

        /** A view of email matching some kind of search criteria. */
        SEARCH,

        /** A folder with an application-defined use. */
        CUSTOM;


        public bool is_outgoing() {
            return this == SENT || this == OUTBOX;
        }

    }

    [Flags]
    public enum CountChangeReason {
        NONE = 0,
        APPENDED,
        INSERTED,
        REMOVED
    }

    /**
     * Flags modifying how email is retrieved.
     */
    [Flags]
    public enum ListFlags {
        NONE = 0,
        /**
         * Fetch from the local store only.
         */
        LOCAL_ONLY,
        /**
         * Fetch from remote store only (results merged into local store).
         */
        FORCE_UPDATE,
        /**
         * Include the provided EmailIdentifier (only respected by {@link list_email_by_id_async}.
         */
        INCLUDING_ID,
        /**
         * Direction of list traversal (if not set, from newest to oldest).
         */
        OLDEST_TO_NEWEST,
        /**
         * Internal use only, prevents flag changes updating unread count.
         */
        NO_UNREAD_UPDATE;

        public bool is_any_set(ListFlags flags) {
            return (this & flags) != 0;
        }

        public bool is_all_set(ListFlags flags) {
            return (this & flags) == flags;
        }

        public bool is_local_only() {
            return is_all_set(LOCAL_ONLY);
        }

        public bool is_force_update() {
            return is_all_set(FORCE_UPDATE);
        }

        public bool is_including_id() {
            return is_all_set(INCLUDING_ID);
        }

        public bool is_oldest_to_newest() {
            return is_all_set(OLDEST_TO_NEWEST);
        }

        public bool is_newest_to_oldest() {
            return !is_oldest_to_newest();
        }
    }

    /** The account that owns this folder. */
    public abstract Geary.Account account { get; }

    /** Current properties for this folder. */
    public abstract Geary.FolderProperties properties { get; }

    /** The path to this folder in the account's folder hierarchy. */
    public abstract Path path { get; }

    /**
     * Determines the special use of this folder.
     *
     * This will be set by the engine and updated as information about
     * a folders use is discovered and changed.
     *
     * @see use_changed
     * @see set_used_as_custom
     */
    public abstract SpecialUse used_as { get; }



    /**
     * Fired when email has been appended to the folder.
     *
     * The {@link EmailIdentifier} for all appended messages is
     * supplied as a signal parameter. The messages have been added to
     * the "top" of the vector of messages, for example, newly
     * delivered email.
     *
     * @see email_inserted
     */
    public virtual signal void email_appended(Gee.Collection<EmailIdentifier> ids) {
        this.account.email_appended_to_folder(this, ids);
    }

    /**
     * Fired when email has been inserted into the folder.
     *
     * The {@link EmailIdentifier} for all inserted messages is
     * supplied as a signal parameter. Inserted messages are not added
     * to the "top" of the vector of messages, but rather into the
     * middle or beginning. This can happen for a number of reasons,
     * including vector expansion, but note that newly received
     * messages are appended and notified via {@link email_appended}.
     *
     * @see email_appended
     */
    public virtual signal void email_inserted(Gee.Collection<EmailIdentifier> ids) {
        this.account.email_inserted_into_folder(this, ids);
    }

    /**
     * Fired when email has been removed (deleted or moved) from the folder.
     *
     * This may occur due to the local user's action or reported from the server (i.e. another
     * client has performed the action).  Email positions greater than the removed emails are
     * affected.
     *
     * ''Note:'' It's possible for the remote server to report a message has been removed that is not
     * known locally (and therefore the caller could not have record of).  If this happens, this
     * signal will ''not'' fire, although {@link email_count_changed} will.
     */
    public virtual signal void email_removed(Gee.Collection<EmailIdentifier> ids) {
        this.account.email_removed_from_folder(this, ids);
    }

    /**
     * Fired when the supplied email flags have changed, whether due to local action or reported by
     * the server.
     */
    public virtual signal void email_flags_changed(Gee.Map<EmailIdentifier,EmailFlags> map) {
        this.account.email_flags_changed_in_folder(this, map);
    }

    /**
     * Fired when the total count of email in a folder has changed in any way.
     *
     * Note that this signal will fire after {@link email_appended},
     * and {@link email_removed} (although see the note at
     * email_removed).
     */
    public virtual signal void email_count_changed(int new_count, CountChangeReason reason);

    /**
     * Fired when the folder's special use has changed.
     *
     * This will usually happen when the local object has been updated
     * with data discovered from the remote account.
     */
    public virtual signal void use_changed(SpecialUse old_use, SpecialUse new_use);


    /**
     * Determines which of the given identifiers are contained by the folder.
     */
    public abstract async Gee.Collection<EmailIdentifier> contains_identifiers(
        Gee.Collection<EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null)
    throws GLib.Error;

    /**
     * List a number of contiguous emails in the folder's vector.
     *
     * Emails in the folder are listed starting at a particular
     * location within the vector and moving either direction along
     * it. For remote-backed folders, the remote server is contacted
     * if any messages stored locally do not meet the requirements
     * given by `required_fields`, or if `count` extends back past the
     * low end of the vector.
     *
     * If the {@link EmailIdentifier} is null, it indicates the end of
     * the vector, not the end of the remote.  Which end depends on
     * the {@link ListFlags.OLDEST_TO_NEWEST} flag.  If not set, the
     * default is to traverse from newest to oldest, with null being
     * the newest email in the vector. If set, the direction is
     * reversed and null indicates the oldest email in the vector, not
     * the oldest in the mailbox.
     *
     * If not null, the EmailIdentifier ''must'' have originated from
     * this Folder.
     *
     * To fetch all available messages in one call, use a count of
     * `int.MAX`. If the {@link ListFlags.OLDEST_TO_NEWEST} flag is
     * set then the listing will contain all messages in the vector,
     * and no expansion will be performed. It may still access the
     * remote however in case of any of the messages not meeting the
     * given `required_fields`. If {@link ListFlags.OLDEST_TO_NEWEST}
     * is not set, the call will cause the vector to be fully expanded
     * and the listing will return all messages in the remote
     * mailbox. Note that specifying `int.MAX` in either case may be a
     * expensive operation (in terms of both computation and memory)
     * if the number of messages in the folder or mailbox is large,
     * hence should be avoided if possible.
     *
     * Use {@link ListFlags.INCLUDING_ID} to include the {@link Email}
     * for the particular identifier in the results.  Otherwise, the
     * specified email will not be included.  A null EmailIdentifier
     * implies that the top most email is included in the result (i.e.
     * ListFlags.INCLUDING_ID is not required);
     *
     * If the remote connection fails, this call will return
     * locally-available Email without error.
     *
     * There's no guarantee of the returned messages' order.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Gee.List<Geary.Email>? list_email_by_id_async(Geary.EmailIdentifier? initial_id,
        int count, Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable = null)
        throws Error;

    /**
     * List a set of non-contiguous emails in the folder's vector.
     *
     * Similar in contract to {@link list_email_by_id_async}, but uses a list of
     * {@link Geary.EmailIdentifier}s rather than a range.
     *
     * Any Gee.Collection is accepted for EmailIdentifiers, but the returned list will only contain
     * one email for each requested; duplicates are ignored.  ListFlags.INCLUDING_ID is ignored
     * for this call.
     *
     * If the remote connection fails, this call will return locally-available Email without error.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Gee.List<Geary.Email>? list_email_by_sparse_id_async(
        Gee.Collection<Geary.EmailIdentifier> ids, Geary.Email.Field required_fields, ListFlags flags,
        Cancellable? cancellable = null) throws Error;

    /**
     * Returns a single email that fulfills the required_fields flag at the ordered position in
     * the folder.  If the email_id is invalid for the folder's contents, an EngineError.NOT_FOUND
     * error is thrown.  If the requested fields are not available, EngineError.INCOMPLETE_MESSAGE
     * is thrown.
     *
     * Because fetch_email_async() is a form of listing (listing exactly one email), it takes
     * ListFlags as a parameter.  See list_email_async() for more information.  Note that one
     * flag (ListFlags.EXCLUDING_ID) makes no sense in this context.
     *
     * This method also works like the list variants in that it will not wait for the server to
     * connect if called in the OPENING state.  A ListFlag option may be offered in the future to
     * force waiting for the server to connect.  Unlike the list variants, if in the OPENING state
     * and the message is not found locally, EngineError.NOT_FOUND is thrown.
     *
     * The Folder must be opened prior to attempting this operation.
     */
    public abstract async Geary.Email fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, ListFlags flags, Cancellable? cancellable = null) throws Error;

    /**
     * Sets whether this folder has a custom special use.
     *
     * If `true`, this set a folder's {@link used_as} property so that
     * it returns {@link SpecialUse.CUSTOM}. If the folder's existing
     * special use is not currently set to {@link SpecialUse.NONE}
     * then {@link EngineError.UNSUPPORTED} is thrown.
     *
     * If `false` and the folder's use is currently {@link
     * SpecialUse.CUSTOM} then it is reset to be {@link
     * SpecialUse.NONE}, otherwise if the folder's use is something
     * other than {@link SpecialUse.NONE} then {@link
     * EngineError.UNSUPPORTED} is thrown.
     *
     * If some other engine process causes this folder's use to be
     * something other than {@link SpecialUse.NONE}, this will
     * override the custom use.
     *
     * @see used_as
     */
    public abstract void set_used_as_custom(bool enabled)
        throws EngineError.UNSUPPORTED;

}
