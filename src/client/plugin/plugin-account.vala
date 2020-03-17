/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An object representing an account for use by plugins.
 *
 * Instances of these may be obtained from their respective {@link
 * Folder} objects.
 */
public interface Plugin.Account : Geary.BaseObject {


    /** Returns the human-readable name of this account. */
    public abstract string display_name { get; }


}
