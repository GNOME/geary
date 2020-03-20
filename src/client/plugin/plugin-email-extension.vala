/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A plugin extension point for working with email messages.
 */
public interface Plugin.EmailExtension : PluginBase {

    /**
     * Context object for accessing email.
     *
     * This will be set during (or just after) plugin construction,
     * before {@link PluginBase.activate} is called.
     */
    public abstract EmailContext email {
        get; set construct;
    }

}


// XXX this should be an inner interface of EmailExtension, but
// GNOME/vala#918 prevents that.

/**
 * Provides a context for email plugins.
 *
 * The context provides an interface for email plugins to interface
 * with the Geary client application. Plugins that implement the
 * {@link EmailExtension} interface will be given an instance of this
 * class.
 *
 * @see Plugin.EmailExtension.email
 */
public interface Plugin.EmailContext : Geary.BaseObject {


    /**
     * Returns a store to lookup email.
     *
     * This method may prompt for permission before returning.
     *
     * @throws Error.PERMISSIONS if permission to access
     * this resource was not given
     */
    public abstract async EmailStore get_email()
        throws Error.PERMISSION_DENIED;

}
