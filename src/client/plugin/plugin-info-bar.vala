/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Enables plugins to report ongoing status messages.
 *
 * The info bar supports two text descriptions, a short (approximately
 * 20 charters at most) status message, and a possibly longer
 * explanation of what is happening.
 */
public class Plugin.InfoBar : Geary.BaseObject {


    /**
     * A short, human-readable status message.
     *
     * This should ideally be less than 20 characters long.
     */
    public string status { get; private set; }

    /**
     * An optional, longer human-readable explanation of the status.
     *
     * This provides additional information and context for {@link
     * status}.
     */
    public string? description { get; private set; }

    /** Determines if a close button is displayed by the info bar. */
    public bool show_close_button { get; set; default = false; }


    /** Constructs a new info bar with the given status. */
    public InfoBar(string status,
                   string? description = null) {
        this.status = status;
        this.description = description;
    }

}
