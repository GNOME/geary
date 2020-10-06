/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.App.FillWindowOperation : ConversationOperation {


    // Maximum and minimum number of messages to load in one fill
    // operation. The maximum exists to retain some degree of
    // responsiveness when loading conversations, given we must load
    // the conversation closure for each message loaded here: Loading
    // a single email might cause a conversation with tens of messages
    // to also have to be pulled in, so the max provides some kind up
    // upper bound to mitigate huge loads and start delivering
    // conversations sooner rather than later. The minimum ensures
    // that enough new messages are found in one operation to justify
    // the expense.
    private const int MAX_FILL_COUNT = 20;
    private const int MIN_FILL_COUNT = 5;


    public FillWindowOperation(ConversationMonitor monitor) {
        base(monitor, false);
    }

    public override async void execute_async() throws Error {
        int num_to_load = (int) (
            (this.monitor.min_window_count - this.monitor.conversations.size)
        );
        if (num_to_load < MIN_FILL_COUNT) {
            num_to_load = MIN_FILL_COUNT;
        } else if (num_to_load > MAX_FILL_COUNT) {
            num_to_load = MAX_FILL_COUNT;
        }

        int loaded = 0;

        try {
            loaded = yield this.monitor.load_by_id_async(
                this.monitor.window_lowest, num_to_load, LOCAL_ONLY
            );
        } catch (EngineError.NOT_FOUND err) {
            debug("Stale FillWindowOperation: %s", err.message);
            return;
        }

        debug(
            "Filled %d of %d locally, window: %d, total: %d",
            loaded, num_to_load,
            this.monitor.conversations.size,
            this.monitor.base_folder.properties.email_total
        );

        if (loaded < num_to_load &&
            this.monitor.can_load_more &&
            this.monitor.base_folder.get_open_state() == REMOTE) {
            // Not enough were loaded locally, but the remote seems to
            // be online and it looks like there and there might be
            // some more on the remote, so go see if there are any.
            //
            // XXX Ideally this would be performed as an explicit user
            // action

            // Load the max amount if going to the trouble of talking
            // to the remote.
            num_to_load = MAX_FILL_COUNT;
            try {
                loaded = yield this.monitor.load_by_id_async(
                    this.monitor.window_lowest, num_to_load, FORCE_UPDATE
                );
            } catch (EngineError.NOT_FOUND err) {
                debug("Stale FillWindowOperation: %s", err.message);
                return;
            }

            debug(
                "Filled %d of %d from the remote, window: %d, total: %d",
                loaded, num_to_load,
                this.monitor.conversations.size,
                this.monitor.base_folder.properties.email_total
            );

        }

        if (loaded == num_to_load) {
            // Loaded the maximum number of messages, so go see if
            // there are any more needed.
            this.monitor.check_window_count();
        } else {
            this.monitor.fill_complete = true;
        }

    }
}
