/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * Application interface for objects that manage accounts.
 *
 * This interface allows non-core application components to access the
 * application's account context objects. Typically this is
 * implemented by {@link Controller}.
 *
 * It also supports unit testing these components without having to
 * load the complete application by providing mock instances of this
 * interface instead of a fully initialised controller.
 */
internal interface Application.AccountInterface : GLib.Object {

    /**
     * Emitted when an account is added or is enabled.
     *
     * This will be emitted after an account is opened and added to
     * the controller.
     *
     * The `is_startup` argument will be true if the application is in
     * the middle of starting up, otherwise if the account was newly
     * added when the application was already running then it will be
     * false.
     */
    public signal void account_available(
        AccountContext context,
        bool is_startup
    );

    /**
     * Emitted when an account is removed or is disabled.
     *
     * This will be emitted after the account is removed from the
     * controller's collection of accounts, but before the {@link
     * AccountContext.cancellable} is cancelled and before the account
     * itself is closed.
     *
     * The `is_shutdown` argument will be true if the application is
     * in the middle of quitting, otherwise if the account was simply
     * removed but the application will keep running, then it will be
     * false.
     */
    public signal void account_unavailable(
        AccountContext context,
        bool is_shutdown
    );

    /** Returns a context for an account, if any. */
    internal abstract AccountContext? get_context_for_account(Geary.AccountInformation account);

    /** Returns a read-only collection of contexts each active account. */
    internal abstract Gee.Collection<AccountContext> get_account_contexts();


}
