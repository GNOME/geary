/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Represents an IMAP mailbox name or path (more commonly known as a folder).
 *
 * Can also be used to specify a wildcarded name for the {@link ListCommand}.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-5.1]]
 */

public class Geary.Imap.MailboxSpecifier : BaseObject, Gee.Hashable<MailboxSpecifier>, Gee.Comparable<MailboxSpecifier> {
    // all references to Inbox are converted to this string, purely for sanity sake when dealing
    // with Inbox's case issues
    public const string CANONICAL_INBOX_NAME = "INBOX";
    
    /**
     * An instance of an Inbox MailboxSpecifier.
     *
     * This is a utility for creating the single IMAP Inbox.  {@link compare_to}. {@link hash},
     * and {@link equal_to} do not rely on this instance for comparison.
     */
    private static MailboxSpecifier? _inbox = null;
    public static MailboxSpecifier inbox {
        get {
            return (_inbox != null) ? _inbox : _inbox = new MailboxSpecifier(CANONICAL_INBOX_NAME);
        }
    }
    
    /**
     * Decoded mailbox path name.
     */
    public string name { get; private set; }
    
    /**
     * Indicates this is the {@link StatusData} for Inbox.
     *
     * IMAP guarantees only one mailbox in an account: Inbox.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-5.1]]
     */
    public bool is_inbox { get; private set; }
    
    public MailboxSpecifier(string name) {
        init(name);
    }
    
    public MailboxSpecifier.from_parameter(MailboxParameter param) {
        init(param.decode());
    }
    
    /**
     * Returns true if the {@link Geary.FolderPath} points to the IMAP Inbox.
     */
    public static bool folder_path_is_inbox(FolderPath path) {
        return path.is_root() && is_inbox_name(path.basename);
    }
    
    /**
     * Returns true if the string is the name of the IMAP Inbox.
     *
     * This accounts for IMAP's Inbox name being case-insensitive.  This is only for comparing
     * folder basenames; this does not account for path delimiters.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-5.1]]
     *
     * @see is_canonical_inbox_name
     */
    public static bool is_inbox_name(string name) {
        return name.up() == CANONICAL_INBOX_NAME;
    }
    
    /**
     * Returns true if the string is the ''canonical'' name of the IMAP Inbox.
     *
     * For sanity reasons, the Geary engine uses {@link CANONICAL_INBOX_NAME} as the "canonical"
     * IMAP Inbox name.  This verifies that the string is truly canonical, i.e. a case-sensitive
     * comparison is made.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-5.1]]
     *
     * @see is_inbox_name
     */
    public static bool is_canonical_inbox_name(string name) {
        return name == CANONICAL_INBOX_NAME;
    }
    
    /**
     * Converts a generic {@link FolderPath} into an IMAP mailbox specifier.
     *
     * If the delimiter was supplied from a {@link ListCommand} response, it can be supplied here.
     * Otherwise, the path's {@link FolderRoot.default_separator} will be used.  If neither have a
     * separator, {@link ImapError.INVALID} is thrown.
     */
    public MailboxSpecifier.from_folder_path(FolderPath path, string? delim) throws ImapError {
        string? fullpath = path.get_fullpath(delim);
        if (fullpath == null) {
            throw new ImapError.INVALID("Unable to convert FolderPath to MailboxSpecifier: no delimiter for %s",
                path.to_string());
        }
        
        init(fullpath);
    }
    
    private void init(string decoded) {
        name = decoded;
        is_inbox = is_inbox_name(decoded);
    }
    
    /**
     * The mailbox's path as a list of strings.
     *
     * Will always return a list with at least one element in it.  If no delimiter is specified,
     * the name is returned as a single element.
     */
    public Gee.List<string> to_list(string? delim) {
        Gee.List<string> path = new Gee.ArrayList<string>();
        
        if (!String.is_empty(delim)) {
            string[] split = name.split(delim);
            foreach (string str in split) {
                if (!String.is_empty(str))
                    path.add(str);
            }
        }
        
        if (path.size == 0)
            path.add(name);
        
        return path;
    }
    
    public FolderPath to_folder_path(string? delim = null) {
        Gee.List<string> list = to_list(delim);
        FolderPath path = new Imap.FolderRoot(list[0], delim);
        for (int ctr = 1; ctr < list.size; ctr++)
            path = path.get_child(list[ctr]);
        
        return path;
    }
    
    /**
     * The mailbox's name without parent folders.
     *
     * If name is non-empty, will return a non-empty value which is the final folder name (i.e.
     * the parent components are stripped).  If no delimiter is specified, the name is returned.
     */
    public string get_basename(string? delim) {
        if (String.is_empty(delim))
            return name;
        
        int index = name.last_index_of(delim);
        if (index < 0)
            return name;
        
        string basename = name.substring(index + 1);
        
        return !String.is_empty(basename) ? basename : name;
    }
    
    public Parameter to_parameter() {
        return new MailboxParameter(name);
    }
    
    public uint hash() {
        return is_inbox ? String.stri_hash(name) : name.hash();
    }
    
    public bool equal_to(MailboxSpecifier other) {
        if (this == other)
            return true;
        
        if (is_inbox)
            return String.stri_equal(name, other.name);
        
        return name == other.name;
    }
    
    public int compare_to(MailboxSpecifier other) {
        if (this == other)
            return 0;
        
        if (is_inbox && other.is_inbox)
            return 0;
        
        return strcmp(name, other.name);
    }
    
    public string to_string() {
        return name;
    }
}

