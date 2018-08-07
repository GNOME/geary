/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of the various built-in email service providers Geary supports.
 */

public enum Geary.ServiceProvider {
    GMAIL,
    YAHOO,
    OUTLOOK,
    OTHER;

    public static ServiceProvider for_value(string value)
        throws EngineError {
        switch (value.ascii_up()) {
        case "GMAIL":
            return GMAIL;
        case "YAHOO":
            return YAHOO;
        case "OUTLOOK":
            return OUTLOOK;
        case "OTHER":
            return OTHER;
        }
        throw new EngineError.BAD_PARAMETERS(
            "Unknown Geary.ServiceProvider value: %s", value
        );
    }

    public string to_value() {
        string value = to_string();
        return value.substring(value.last_index_of("_") + 1);
    }

}
