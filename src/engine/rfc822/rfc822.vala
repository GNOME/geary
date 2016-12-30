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

/**
 * Official IANA charset encoding name for UTF-8.
 */
public const string UTF8_CHARSET = "UTF-8";

// This has the effect of ensuring all non US-ASCII and non-ISO-8859-1
// headers are always encoded as UTF-8. This should be fine because
// message bodies are also always sent as UTF-8.
private const string[] USER_CHARSETS =  { UTF8_CHARSET };

private int init_count = 0;

internal Regex? invalid_filename_character_re = null;

public void init() {
    if (init_count++ != 0)
        return;

    GMime.init(GMime.ENABLE_RFC2047_WORKAROUNDS);
    GMime.set_user_charsets(USER_CHARSETS);

    try {
        invalid_filename_character_re = new Regex("[/\\0]");
    } catch (RegexError e) {
        assert_not_reached();
    }
}

}
