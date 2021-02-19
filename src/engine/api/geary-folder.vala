/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018-2021 Michael Gratton <mike@vee.net>
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
 * folder methods return instances of these.
 *
 * The set of email in a folder is called the folder's ''vector'', and
 * contains generally the most recent message in the mailbox at the
 * upper end, back through to some older message at the start or lower
 * end of the vector. The ordering of the vector is the ''natural''
 * ordering, based on the order in which messages were appended to the
 * folder, not when messages were sent or some other criteria.
 *
 * Folders that represent a remote folder extend {@link
 * RemoteFolder}. These cache the remote folder's email locally in the
 * vector, and these messages may be a subset of those available in
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

    /**
     * Flags modifying retrieval of specific email from the vector.
     *
     * @see get_email_by_id
     * @see get_multiple_email_by_id
     */
    [Flags]
    public enum GetFlags {

        NONE = 0,

        /** Include email that only partially matches the requested fields. */
        INCLUDING_PARTIAL;

    }

    /**
     * Flags for modifying retrieval of ranges of email from the vector.
     *
     * @see list_email_range_by_id
     */
    [Flags]
    public enum ListFlags {

        NONE = 0,

        /** Include the email with the given identifier in the range. */
        INCLUDING_ID,

        /** Include email that only partially matches the requested fields. */
        INCLUDING_PARTIAL,

        /** Return email ordered oldest to newest, instead of the default. */
        OLDEST_TO_NEWEST;


        public bool is_any_set(ListFlags flags) {
            return (this & flags) != 0;
        }

        public bool is_all_set(ListFlags flags) {
            return (this & flags) == flags;
        }

        public bool is_including_id() {
            return is_all_set(INCLUDING_ID);
        }

        public bool is_newest_to_oldest() {
            return !is_oldest_to_newest();
        }

        public bool is_oldest_to_newest() {
            return is_all_set(OLDEST_TO_NEWEST);
        }

    }


    /** The account that owns this folder. */
    public abstract Geary.Account account { get; }

    /** The path to this folder in the account's folder hierarchy. */
    public abstract Path path { get; }

    /** The total number of email messages in this folder. */
    public abstract int email_total { get; }

    /** The number of unread email messages in this folder. */
    public abstract int email_unread { get; }

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
     * This will be default also emit {@link
     * Account.email_appended_to_folder}.
     *
     * @see email_inserted
     * @see Account.email_appended_to_folder
     */
    public virtual signal void email_appended(
        Gee.Collection<EmailIdentifier> ids
    ) {
        this.account.email_appended_to_folder(ids, this);
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
     * This will be default also emit {@link
     * Account.email_inserted_into_folder}.
     *
     * @see email_appended
     * @see Account.email_inserted_into_folder
     */
    public virtual signal void email_inserted(
        Gee.Collection<EmailIdentifier> ids
    ) {
        this.account.email_inserted_into_folder(ids, this);
    }

    /**
     * Fired when email has been removed (deleted or moved) from the folder.
     *
     * This may occur due to the local user's action or reported from
     * the server (i.e. another client has performed the action).
     * Email positions greater than the removed emails are affected.
     *
     * This will be default also emit {@link
     * Account.email_removed_from_folder}.
     *
     * @see Account.email_removed_from_folder
     */
    public virtual signal void email_removed(
        Gee.Collection<EmailIdentifier> ids
    ) {
        this.account.email_removed_from_folder(ids, this);
    }

    /**
     * Fired when the supplied email flags have changed, whether due to local action or reported by
     * the server.
     *
     * This will be default also emit {@link
     * Account.email_flags_changed_in_folder}.
     *
     * @see Account.email_flags_changed_in_folder
     */
    public virtual signal void email_flags_changed(
        Gee.Map<EmailIdentifier,EmailFlags> map
    ) {
        this.account.email_flags_changed_in_folder(map, this);
    }

    /**
     * Fired when the folder's special use has changed.
     *
     * This will usually happen when the local object has been updated
     * with data discovered from the remote account.
     *
     * @see Account.folders_use_changed
     */
    public virtual signal void use_changed(
        SpecialUse old_use, SpecialUse new_use
    );


    /**
     * Determines which of the given identifiers are contained by the folder.
     */
    public abstract async Gee.Collection<EmailIdentifier> contains_identifiers(
        Gee.Collection<EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null)
    throws GLib.Error;

    /**
     * Returns an email from the folder's vector.
     *
     * The returned email object will have its property values set for
     * at least all requested fields, others may or may not be. If is
     * good practice for callers request only the fields be loaded
     * that they actually require, since the time taken to load the
     * message will be reduced as there will be less data to load from
     * local storage.
     *
     * Note that for remote-backed folders, an email may not have yet
     * been fully downloaded and hence might exist incomplete in local
     * storage. If the requested fields are not available, {@link
     * EngineError.INCOMPLETE_MESSAGE} is thrown, unless the {@link
     * GetFlags.INCLUDING_PARTIAL} in specified. Connect to the {@link
     * Account.email_complete} signal to be notified of when email is
     * fully downloaded in this case.
     *
     * If the given email identifier is not present in the vector, an
     * {@link EngineError.NOT_FOUND} error is thrown.
     *
     * @see Account.get_email_by_id
     */
    public abstract async Geary.Email get_email_by_id(
        EmailIdentifier email_id,
        Email.Field required_fields = ALL,
        GetFlags flags = NONE,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error;

    /**
     * Returns a set of emails from the folder's vector.
     *
     * Similar in contract to {@link get_email_by_id}, but for a
     * collection of {@link Geary.EmailIdentifier}s rather than a
     * single email.
     *
     * Any {@link Gee.Collection} of email identifiers is accepted,
     * but the returned set will only contain one email for each
     * requested; duplicates are ignored.
     *
     * Note that for remote-backed folders, email may not have yet
     * been fully downloaded and hence might exist incomplete in local
     * storage. If the requested fields are not available for all
     * given identifiers, {@link EngineError.INCOMPLETE_MESSAGE} is
     * thrown, unless the {@link GetFlags.INCLUDING_PARTIAL} in
     * specified. Connect to the {@link Account.email_complete} signal
     * to be notified of when email is fully downloaded in this case.
     *
     * If any of the given email identifiers are not present in the
     * vector, an {@link EngineError.NOT_FOUND} error is thrown.
     *
     * @see Account.get_multiple_email_by_id
     */
    public abstract async Gee.Set<Email> get_multiple_email_by_id(
        Gee.Collection<EmailIdentifier> ids,
        Email.Field required_fields = ALL,
        GetFlags flags = NONE,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error;

    /**
     * List a number of contiguous emails in the folder's vector.
     *
     * Emails in the folder are listed starting at a particular
     * location within the vector and moving either direction along
     * it.
     *
     * If the given identifier is null, it indicates the end of the
     * vector (not the end of the remote for remote-backed folders).
     * Which end depends on the {@link ListFlags.OLDEST_TO_NEWEST}
     * flag. If not set, the default is to traverse from newest to
     * oldest, with null being the newest email in the vector. If set,
     * the direction is reversed and null indicates the oldest email
     * in the vector, not the oldest in the mailbox.
     *
     * If not null, the EmailIdentifier ''must'' have originated from
     * this folder.
     *
     * To fetch all available messages in one call, use a count of
     * `int.MAX`. Note that this can be an extremely expensive
     * operation.
     *
     * Note that for remote-backed folders, email may not have yet
     * been fully downloaded and hence might exist incomplete in local
     * storage. If the requested fields are not available for all
     * email in the range, {@link EngineError.INCOMPLETE_MESSAGE} is
     * thrown. Use {@link ListFlags.INCLUDING_PARTIAL} to allow email
     * that does not meet the given criteria to be included in the
     * results, and connect to the {@link Account.email_complete}
     * signal to be notified of when those email are fully downloaded.
     *
     * Use {@link ListFlags.INCLUDING_ID} to include the {@link Email}
     * for the particular identifier in the results.  Otherwise, the
     * specified email will not be included. A null identifier implies
     * that the top most email is included in the result (i.e.
     * ListFlags.INCLUDING_ID is not required);
     *
     * Email is returned listed by the vector's natural ordering, in
     * the direction given by the given list flags.
     */
    public abstract async Gee.List<Email> list_email_range_by_id(
        EmailIdentifier? initial_id,
        int count,
        Email.Field required_fields,
        ListFlags flags,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error;

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
