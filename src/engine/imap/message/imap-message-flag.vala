/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An IMAP message (email) flag.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-2.3.2]]
 *
 * @see StoreCommand
 * @see FetchCommand
 * @see FetchedData
 */

public class Geary.Imap.MessageFlag : Geary.Imap.Flag {
    private static MessageFlag? _answered = null;
    public static MessageFlag ANSWERED { get {
        if (_answered == null)
            _answered = new MessageFlag("\\answered");
        
        return _answered;
    } }
    
    private static MessageFlag? _deleted = null;
    public static MessageFlag DELETED { get {
        if (_deleted == null)
            _deleted = new MessageFlag("\\deleted");
        
        return _deleted;
    } }
    
    private static MessageFlag? _draft = null;
    public static MessageFlag DRAFT { get {
        if (_draft == null)
            _draft = new MessageFlag("\\draft");
        
        return _draft;
    } }
    
    private static MessageFlag? _flagged = null;
    public static MessageFlag FLAGGED { get {
        if (_flagged == null)
            _flagged = new MessageFlag("\\flagged");
        
        return _flagged;
    } }
    
    private static MessageFlag? _recent = null;
    public static MessageFlag RECENT { get {
        if (_recent == null)
            _recent = new MessageFlag("\\recent");
        
        return _recent;
    } }
    
    private static MessageFlag? _seen = null;
    public static MessageFlag SEEN { get {
        if (_seen == null)
            _seen = new MessageFlag("\\seen");
        
        return _seen;
    } }
    
    private static MessageFlag? _allows_new = null;
    public static MessageFlag ALLOWS_NEW { get {
        if (_allows_new == null)
            _allows_new = new MessageFlag("\\*");
        
        return _allows_new;
    } }
    
    private static MessageFlag? _load_remote_images = null;
    public static MessageFlag LOAD_REMOTE_IMAGES { get {
        if (_load_remote_images == null)
            _load_remote_images = new MessageFlag("LoadRemoteImages");
        
        return _load_remote_images;
    } }
    
    public MessageFlag(string value) {
        base (value);
    }
    
    // Call these at init time to prevent thread issues
    internal static void init() {
        MessageFlag to_init = ANSWERED;
        to_init = DELETED;
        to_init = DRAFT;
        to_init = FLAGGED;
        to_init = RECENT;
        to_init = SEEN;
        to_init = ALLOWS_NEW;
    }
    
    // Converts a list of email flags to add and remove to a list of message
    // flags to add and remove.
    public static void from_email_flags(Geary.EmailFlags? email_flags_add, 
        Geary.EmailFlags? email_flags_remove, out Gee.List<MessageFlag> msg_flags_add,
        out Gee.List<MessageFlag> msg_flags_remove) {
        msg_flags_add = new Gee.ArrayList<MessageFlag>();
        msg_flags_remove = new Gee.ArrayList<MessageFlag>();

        if (email_flags_add != null) {
            if (email_flags_add.contains(Geary.EmailFlags.UNREAD))
                msg_flags_remove.add(MessageFlag.SEEN);
            if (email_flags_add.contains(Geary.EmailFlags.FLAGGED))
                msg_flags_add.add(MessageFlag.FLAGGED);
            if (email_flags_add.contains(Geary.EmailFlags.LOAD_REMOTE_IMAGES))
                msg_flags_add.add(MessageFlag.LOAD_REMOTE_IMAGES);
        }

        if (email_flags_remove != null) {
            if (email_flags_remove.contains(Geary.EmailFlags.UNREAD))
                msg_flags_add.add(MessageFlag.SEEN);
            if (email_flags_remove.contains(Geary.EmailFlags.FLAGGED))
                msg_flags_remove.add(MessageFlag.FLAGGED);
            if (email_flags_remove.contains(Geary.EmailFlags.LOAD_REMOTE_IMAGES))
                msg_flags_remove.add(MessageFlag.LOAD_REMOTE_IMAGES);
        }
    }
}

