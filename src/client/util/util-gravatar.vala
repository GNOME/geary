/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Gravatar {

public const int MIN_SIZE = 1;
public const int MAX_SIZE = 512;
public const int DEFAULT_SIZE = 80;

public enum Default {
    NOT_FOUND,
    MYSTERY_MAN,
    IDENTICON,
    MONSTER_ID,
    WAVATAR,
    RETRO;
    
    public string to_param() {
        switch (this) {
            case NOT_FOUND:
                return "404";
            
            case MYSTERY_MAN:
                return "mm";
            
            case IDENTICON:
                return "identicon";
            
            case MONSTER_ID:
                return "monsterid";
            
            case WAVATAR:
                return "wavatar";
            
            case RETRO:
                return "retro";
            
            default:
                assert_not_reached();
        }
    }
}

/**
 * Returns a URI for the mailbox address specified.  size may be any value from MIN_SIZE to
 * MAX_SIZE, representing pixels.  This function does not attempt to clamp size to this range or
 * return an error of any kind if it's outside this range.
 *
 * TODO: More parameters are available and could be incorporated.  See
 * https://en.gravatar.com/site/implement/images/
 */
public string get_image_uri(Geary.RFC822.MailboxAddress addr, Default def, int size = DEFAULT_SIZE) {
    return "http://www.gravatar.com/avatar/%s?d=%s&s=%d".printf(
        Checksum.compute_for_string(ChecksumType.MD5, addr.address), def.to_param(), size);
}

}

