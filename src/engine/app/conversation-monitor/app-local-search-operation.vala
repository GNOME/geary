/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.LocalSearchOperation : Geary.Nonblocking.BatchOperation {
    // IN
    public Geary.Account account;
    public RFC822.MessageID message_id;
    public Geary.Email.Field required_fields;
    public Gee.Collection<Geary.FolderPath>? blacklist;
    public Geary.EmailFlags? flag_blacklist;

    // OUT
    public Gee.MultiMap<Geary.Email, Geary.FolderPath?>? emails = null;

    public LocalSearchOperation(Geary.Account account, RFC822.MessageID message_id,
        Geary.Email.Field required_fields, Gee.Collection<Geary.FolderPath?> blacklist,
        Geary.EmailFlags? flag_blacklist) {
        this.account = account;
        this.message_id = message_id;
        this.required_fields = required_fields;
        this.blacklist = blacklist;
        this.flag_blacklist = flag_blacklist;
    }

    public override async Object? execute_async(Cancellable? cancellable) throws Error {
        emails = yield account.local_search_message_id_async(message_id, required_fields,
            false, blacklist, flag_blacklist);

        return null;
    }
}
