/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An object representing an email for use by plugins.
 *
 * Instances of these may be obtained from {@link EmailStore}.
 */
public interface Plugin.Email :
    Geary.BaseObject,
    Geary.EmailHeaderSet {


    /** Returns a unique identifier for this email. */
    public abstract EmailIdentifier identifier { get; }

    /** Returns the set of mutable flags for the email. */
    public abstract Geary.EmailFlags flags { get; }

    /**
     * Returns the email's primary originator.
     *
     * This method returns the mailbox of the best originator of the
     * email, if any.
     *
     * @see Util.Email.get_primary_originator
     */
    public abstract Geary.RFC822.MailboxAddress? get_primary_originator();

}


// XXX this should be an inner interface of Email, but GNOME/vala#918
// prevents that.

/**
 * An object representing an email's identifier.
 */
public interface Plugin.EmailIdentifier :
    Geary.BaseObject, Gee.Hashable<EmailIdentifier> {


    /** Returns the account that the email belongs to. */
    public abstract Account account { get; }


    /**
     * Returns a variant version of this identifier.
     *
     * This value is suitable to be used as the `show-email`
     * application action parameter.
     */
    public abstract GLib.Variant to_variant();

}
