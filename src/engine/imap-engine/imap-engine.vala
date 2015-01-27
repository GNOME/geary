/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.ImapEngine {

private int init_count = 0;
private Gee.HashMap<GenericAccount, AccountSynchronizer>? account_synchronizers = null;

internal void init() {
    if (init_count++ != 0)
        return;
    
    account_synchronizers = new Gee.HashMap<GenericAccount, AccountSynchronizer>();
    
    // create a FullAccountSync object for each Account as it comes and goes
    Engine.instance.account_available.connect(on_account_available);
    Engine.instance.account_unavailable.connect(on_account_unavailable);
}

private GenericAccount? get_imap_account(AccountInformation account_info) {
    try {
        return Engine.instance.get_account_instance(account_info) as GenericAccount;
    } catch (Error err) {
        debug("Unable to get account instance %s: %s", account_info.email, err.message);
    }
    
    return null;
}

private void on_account_available(AccountInformation account_info) {
    GenericAccount? imap_account = get_imap_account(account_info);
    if (imap_account == null)
        return;
    
    assert(!account_synchronizers.has_key(imap_account));
    account_synchronizers.set(imap_account, new AccountSynchronizer(imap_account));
}

private void on_account_unavailable(AccountInformation account_info) {
    GenericAccount? imap_account = get_imap_account(account_info);
    if (imap_account == null)
        return;
    
    AccountSynchronizer? account_synchronizer = account_synchronizers.get(imap_account);
    assert(account_synchronizer != null);
    
    account_synchronizer.stop_async.begin(on_synchronizer_stopped);
}

private void on_synchronizer_stopped(Object? source, AsyncResult result) {
    AccountSynchronizer account_synchronizer = (AccountSynchronizer) source;
    account_synchronizer.stop_async.end(result);
    
    bool removed = account_synchronizers.unset(account_synchronizer.account);
    assert(removed);
}

/**
 * A hard failure is defined as one due to hardware or connectivity issues, where a soft failure
 * is due to software reasons, like credential failure or protocol violation.
 */
private static bool is_hard_failure(Error err) {
    // CANCELLED is not a hard error
    if (err is IOError.CANCELLED)
        return false;
    
    // Treat other errors -- most likely IOErrors -- as hard failures
    if (!(err is ImapError) && !(err is EngineError))
        return true;
    
    return err is ImapError.NOT_CONNECTED
        || err is ImapError.TIMED_OUT
        || err is ImapError.SERVER_ERROR
        || err is EngineError.SERVER_UNAVAILABLE;
}

}

