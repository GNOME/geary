/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.EmailIdentifier : Geary.EmailIdentifier {
    public int64 message_id { get; private set; }
    public Imap.UID? uid { get; private set; }
    
    public EmailIdentifier(int64 message_id, Imap.UID? uid) {
        assert(message_id != Db.INVALID_ROWID);
        
        base (message_id.to_string());
        
        this.message_id = message_id;
        this.uid = uid;
    }
    
    // Used when a new message comes off the wire and doesn't have a rowid associated with it (yet)
    // Requires a UID in order to find or create such an association
    public EmailIdentifier.no_message_id(Imap.UID uid) {
        base (Db.INVALID_ROWID.to_string());
        
        message_id = Db.INVALID_ROWID;
        this.uid = uid;
    }
    
    // Used to promote an id created with no_message_id to one that has a
    // message id.  Warning: this causes the hash value to change, so if you
    // have any EmailIdentifiers in a hashed data structure, this will cause
    // you not to be able to find them.
    public void promote_with_message_id(int64 message_id) {
        assert(this.message_id == Db.INVALID_ROWID);
        
        unique = message_id.to_string();
        this.message_id = message_id;
    }
    
    public bool has_uid() {
        return (uid != null) && uid.is_valid();
    }
    
    public override int natural_sort_comparator(Geary.EmailIdentifier o) {
        ImapDB.EmailIdentifier? other = o as ImapDB.EmailIdentifier;
        if (other == null)
            return 1;
        
        if (uid == null)
            return 1;
        
        if (other.uid == null)
            return -1;
        
        return uid.compare_to(other.uid);
    }
    
    public override string to_string() {
        return "[%s/%s]".printf(message_id.to_string(), (uid == null ? "null" : uid.to_string()));
    }
    
    // Email's with no UID get sorted after emails with
    public static int compare_email_uid_ascending(Geary.Email a, Geary.Email b) {
        Imap.UID? auid = ((ImapDB.EmailIdentifier) a.id).uid;
        Imap.UID? buid = ((ImapDB.EmailIdentifier) b.id).uid;
        
        if (auid == null)
            return (buid != null) ? 1 : 0;
        
        if (buid == null)
            return -1;
        
        return auid.compare_to(buid);
    }
    
    public static Gee.Set<Imap.UID> to_uids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        Gee.HashSet<Imap.UID> uids = new Gee.HashSet<Imap.UID>();
        foreach (ImapDB.EmailIdentifier id in ids) {
            if (id.uid != null)
                uids.add(id.uid);
        }
        
        return uids;
    }
}
