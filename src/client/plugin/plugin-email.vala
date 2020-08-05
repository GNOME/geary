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


    /** Defines the formats that email body text can be loaded as. */
    public enum BodyType {
        /** Specifies `text/plain` body parts. */
        PLAIN,
        /** Specifies `text/html` body parts. */
        HTML;
    }


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

    /**
     * Load the text of the email body as the given type.
     *
     * This method traverses the MIME multipart structure of the email
     * body finding inline text parts and assembles them into a
     * complete email body, as would be displayed to a person reading
     * the email. If multiple matching parts are found, they will be
     * concatenated.
     *
     * If no alternative parts for the requested type exist and
     * `convert` is true, if alternatives for other supported types
     * are present, an attempt will be made to convert to the
     * requested type. For example, requesting HTML for an email with
     * plain text only will attempt to reformat the plain text by
     * inserting HTML tags. Otherwise an {@link Error.NOT_SUPPORTED}
     * error is thrown.
     *
     * An error will be thrown if no body parts could be found, for
     * example if an email has not completely been downloaded from the
     * server.
     */
    public abstract async string load_body_as(
        BodyType type,
        bool convert,
        GLib.Cancellable? cancellable
    ) throws GLib.Error;

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
     *
     * @see EmailStore.get_email_identifier_for_variant
     * @see EmailStore.email_identifier_variant_type
     */
    public abstract GLib.Variant to_variant();

}
