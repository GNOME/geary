/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A collection of NamedFlags that can be used to enable/disable various user-defined
 * options for an email message.  System- or Geary-defined flags are available as static
 * members.
 *
 * Note that how flags are represented by a particular email storage system may differ from
 * how they're presented here.  In particular, the manner of serializing and deserializing
 * the flags may be handled by an internal subclass.
 */

public class Geary.EmailFlags : Geary.NamedFlags {
    public static NamedFlag UNREAD { owned get {
        return new NamedFlag("UNREAD");
    } }

    public static NamedFlag FLAGGED { owned get {
        return new NamedFlag("FLAGGED");
    } }

    public static NamedFlag LOAD_REMOTE_IMAGES { owned get {
        return new NamedFlag("LOADREMOTEIMAGES");
    } }
    
    public static NamedFlag DRAFT { owned get {
        return new NamedFlag("DRAFT");
    } }
    
    /// Signifies a message in our outbox that has been sent but we're still
    /// keeping around for other purposes, i.e. pushing up to Sent Mail.
    public static NamedFlag OUTBOX_SENT { owned get {
        // This shouldn't ever touch the wire, so make it invalid IMAP.
        return new NamedFlag(" OUTBOX SENT ");
    } }
    
    public EmailFlags() {
    }
    
    // Convenience method to check if the unread flag is set.
    public inline bool is_unread() {
        return contains(UNREAD);
    }

    public inline bool is_flagged() {
        return contains(FLAGGED);
    }
    
    public inline bool load_remote_images() {
        return contains(LOAD_REMOTE_IMAGES);
    }
    
    public inline bool is_draft() {
        return contains(DRAFT);
    }
    
    public inline bool is_outbox_sent() {
        return contains(OUTBOX_SENT);
    }
}

