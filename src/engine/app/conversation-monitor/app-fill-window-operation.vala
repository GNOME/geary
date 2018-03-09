/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
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

        debug(
            "Filling %d messages in %s...",
            num_to_load, this.monitor.base_folder.to_string()
        );

        int loaded = yield this.monitor.load_by_id_async(
            this.monitor.window_lowest, num_to_load
        );

        // Check to see if we need any more, but only if we actually
        // loaded some, so we don't keep loop loading when we have
        // already loaded all in the folder.
        if (loaded > 0) {
            this.monitor.check_window_count();
        }
    }
}
