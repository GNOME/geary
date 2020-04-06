/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An object representing a composer for use by plugins.
 */
public interface Plugin.Composer : Geary.BaseObject {

    /**
     * Causes the composer to be made visible.
     *
     * The composer will be shown as either full-pane and in-window if
     * not a reply to a currently displayed conversation, inline and
     * in-window if a reply to an existing conversation being
     * displayed, or detached if there is already an in-window
     * composer being displayed.
     */
    public abstract void show();

}
