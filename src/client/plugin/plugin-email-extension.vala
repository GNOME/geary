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
     * @throws Error.PERMISSION_DENIED if permission to access the
     * resource was not given
     */
    public abstract async EmailStore get_email_store()
        throws Error.PERMISSION_DENIED;

    /**
     * Adds an info bar to an email, if displayed.
     *
     * The info bar will be shown for the given email if it is
     * currently displayed in any main window, which can be determined
     * by connecting to the {@link EmailStore.email_displayed}
     * signal. Further, if multiple info bars are added for the same
     * email, only the one with a higher priority will be shown. If
     * that is closed or removed, the second highest will be shown,
     * and so on. Once the email is no longer shown, the info bars
     * will be automatically removed.
     */
    public abstract void add_email_info_bar(EmailIdentifier displayed,
                                            InfoBar info_bar,
                                            uint priority);

    /**
     * Removes an info bar from a email, if displayed.
     *
     * Removes the info bar from the given email if it is currently
     * displayed in any main window.
     */
    public abstract void remove_email_info_bar(EmailIdentifier displayed,
                                               InfoBar info_bar);

}
