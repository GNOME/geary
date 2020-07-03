/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An object representing the client application for use by plugins.
 *
 * Plugins may obtain instances of this object from the {@link
 * PluginBase.plugin_application} property.
 */
public interface Plugin.Application : Geary.BaseObject {


    /**
     * Emitted when a new composer is registered with the application.
     *
     * A composer is registered when it is first constructed.
     *
     * @see Composer.present
     */
    public signal void composer_registered(Composer composer);

    /**
     * Emitted when an existing composer is de-registered.
     *
     * A composer is deregistered when it is destroyed, either after
     * being sent, closed, or discarded.
     */
    public signal void composer_deregistered(Composer composer);


    /**
     * Obtains a new, blank composer for the given account.
     *
     * The composer will be initialised to send an email from the
     * given account. This may be changed via the UI before the email
     * is sent, however.
     *
     * Existing composer instances are re-used where possible, thus if
     * a blank composer is already open, the same instance may be
     * returned if this method is called multiple times.
     */
    public abstract async Composer compose_blank(Account send_from)
        throws Error;

    /**
     * Obtains a new composer with the given message as a context
     *
     * The composer will be initialised to send an email from the
     * given account, with the given email loaded as either an email
     * to edit, a reply, or a forwarded message, depending on the
     * given context.
     *
     * If a quote is given, this added as a quote in the composer's
     * body.
     *
     * Existing composer instances are re-used where possible, thus if
     * a composer with a given context and email is already open, the
     * same instance may be returned if this method is called multiple
     * times with the same arguments.
     *
     * Returns null if there is an existing composer open and the
     * prompt to close it was declined.
     */
    public abstract async Composer? compose_with_context(
        Account send_from,
        Composer.ContextType type,
        EmailIdentifier context,
        string? quote = null
    ) throws Error;

    /**
     * Registers a plugin action with the application.
     *
     * Once registered, the action will be available for use in user
     * interface elements such as {@link Actionable}.
     *
     * @see deregister_action
     */
    public abstract void register_action(GLib.Action action);

    /**
     * De-registers a plugin action with the application.
     *
     * Makes a previously registered no longer available.
     *
     * @see register_action
     */
    public abstract void deregister_action(GLib.Action action);

    /** Displays a folder in the most recently used main window. */
    public abstract void show_folder(Folder folder);

    /**
     * Reversibly deletes all email from a folder.
     *
     * A prompt will be displayed for confirmation before the folder
     * is actually emptied, if declined an exception will be thrown.
     *
     * This method will return once the engine has completed emptying
     * the folder, however it may take additional time for the changes
     * to be fully committed and reflected on the remote server.
     *
     * @throws Error.PERMISSION_DENIED if permission to access the
     * resource was not given
     */
    public abstract async void empty_folder(Folder folder)
        throws Error.PERMISSION_DENIED;


    /**
     * Sends a problem report to the application.
     *
     * Calling this method will display a problem report for the
     * plugin with a given error so that both people using the
     * application are aware that an error condition exists, and that
     * they may report the problem to developers.
     *
     * Since displaying an error report causes visual and workflow
     * disruptions, and as such this method called with care and only
     * when necessary. For logging, use {@link GLib.debug} and related
     * methods and these will appear in Geary's Inspector.
     */
    public abstract void report_problem(Geary.ProblemReport problem);

}
