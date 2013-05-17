/* Copyright 2011-2013 Yorba Foundation
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
    private static NamedFlag? _unread = null;
    public static NamedFlag UNREAD { get {
        if (_unread == null)
            _unread = new NamedFlag("UNREAD");
        
        return _unread;
    } }

    private static NamedFlag? _flagged = null;
    public static NamedFlag FLAGGED { get {
        if (_flagged == null)
            _flagged = new NamedFlag("FLAGGED");

        return _flagged;
    } }

    private static NamedFlag? _load_remote_images = null;
    public static NamedFlag LOAD_REMOTE_IMAGES { get {
        if (_load_remote_images == null)
            _load_remote_images = new NamedFlag("LOADREMOTEIMAGES");
        
        return _load_remote_images;
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
}

