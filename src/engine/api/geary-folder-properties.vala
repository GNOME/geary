/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public abstract class Geary.FolderProperties : BaseObject {
    public const string PROP_NAME_EMAIL_TOTAL = "email-total";
    public const string PROP_NAME_EMAIL_UNDREAD = "email-unread";
    public const string PROP_NAME_HAS_CHILDREN = "has-children";
    public const string PROP_NAME_SUPPORTS_CHILDREN = "supports-children";
    public const string PROP_NAME_IS_OPENABLE = "is-openable";
    
    /**
     * The total count of email in the Folder.
     */
    public int email_total { get; protected set; }
    
    /**
     * The total count of unread email in the Folder.
     */
    public int email_unread { get; protected set; }
    
    /**
     * Returns a Trillian indicating if this Folder has children.  has_children == Trillian.TRUE
     * implies supports_children == Trilian.TRUE.
     */
    public Trillian has_children { get; protected set; }
    
    /**
     * Returns a Trillian indicating if this Folder can parent new children Folders.  This does
     * *not* mean creating a sub-folder is guaranteed to succeed.
     */
    public Trillian supports_children { get; protected set; }
    
    /**
     * Returns a Trillian indicating if Folder.open_async() *can* succeed remotely.
     */
    public Trillian is_openable { get; protected set; }
    
    protected FolderProperties(int email_total, int email_unread, Trillian has_children,
        Trillian supports_children, Trillian is_openable) {
        this.email_total = email_total;
        this.email_unread = email_unread;
        this.has_children = has_children;
        this.supports_children = supports_children;
        this.is_openable = is_openable;
    }
}

