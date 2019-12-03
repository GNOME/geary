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
 * Official IANA charset encoding name for the UTF-8 character set.
 */
public const string UTF8_CHARSET = "UTF-8";

private int init_count = 0;

internal Regex? invalid_filename_character_re = null;

public void init() {
    if (init_count++ != 0)
        return;

    GMime.init();

    try {
        invalid_filename_character_re = new Regex("[/\\0]");
    } catch (RegexError e) {
        assert_not_reached();
    }
}

public GMime.FormatOptions get_format_options() {
    return new GMime.FormatOptions();
}

public GMime.ParserOptions get_parser_options() {
    return new GMime.ParserOptions();
}

public string? get_charset() {
    return UTF8_CHARSET;
}

internal bool is_utf_8(string charset) {
    string up = charset.up();
    return (
        // ASCII is a subset of UTF-8, so it's also valid
        up == "ASCII" ||
        up == "US-ASCII" ||
        up == "US_ASCII" ||
        up == "UTF-8" ||
        up == "UTF8" ||
        up == "UTF_8"
    );
}

}
