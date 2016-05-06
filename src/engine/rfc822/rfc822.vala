/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.RFC822 {

/**
 * Common text formats supported by {@link Geary.RFC822}.
 */
public enum TextFormat {
    PLAIN,
    HTML
}

private int init_count = 0;

internal Regex? invalid_filename_character_re = null;

public void init() {
    if (init_count++ != 0)
        return;
    
    GMime.init(GMime.ENABLE_RFC2047_WORKAROUNDS);
    
    try {
        invalid_filename_character_re = new Regex("[/\\0]");
    } catch (RegexError e) {
        assert_not_reached();
    }
}

}
