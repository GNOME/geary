/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Geary.App.ConversationMonitorTest : TestCase {


    AccountInformation? account_info = null;
    Mock.Account? account = null;
    FolderRoot? folder_root = null;
    Mock.Folder? base_folder = null;
    Mock.Folder? other_folder = null;


    public ConversationMonitorTest() {
        base("Geary.App.ConversationMonitorTest");
        add_test("start_stop_monitoring", start_stop_monitoring);
        add_test("open_error", open_error);
        add_test("close_during_open_error", close_during_open_error);
        add_test("close_after_open_error", close_after_open_error);
        add_test("load_single_message", load_single_message);
        add_test("load_multiple_messages", load_multiple_messages);
        add_test("load_related_message", load_related_message);
        add_test("base_folder_message_appended", base_folder_message_appended);
        add_test("base_folder_message_removed", base_folder_message_removed);
        add_test("external_folder_message_appended", external_folder_message_appended);
        add_test("conversation_marked_as_deleted", conversation_marked_as_deleted);
    }

    public override void set_up() {
        this.account_info = new AccountInformation(
            "account_01",
            ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new RFC822.MailboxAddress(null, "test1@example.com")
        );
        this.account = new Mock.Account(this.account_info);
        this.folder_root = new FolderRoot("#test", false);
        this.base_folder = new Mock.Folder(
            this.account,
            null,
            this.folder_root.get_child("base"),
            NONE,
            null
        );
        this.other_folder = new Mock.Folder(
            this.account,
            null,
            this.folder_root.get_child("other"),
            NONE,
            null
        );
    }

    public override void tear_down() {
        this.other_folder = null;
        this.base_folder = null;
        this.folder_root = null;
        this.account_info = null;
        this.account = null;
    }

    public void start_stop_monitoring() throws Error {
        ConversationMonitor monitor = new ConversationMonitor(
            this.base_folder, Email.Field.NONE, 10
        );
        Cancellable test_cancellable = new Cancellable();

        bool saw_scan_started = false;
        bool saw_scan_completed = false;
        monitor.scan_started.connect(() => { saw_scan_started = true; });
        monitor.scan_completed.connect(() => { saw_scan_completed = true; });

        this.base_folder.expect_call("open_async");
        this.base_folder.expect_call("list_email_by_id_async");
        this.base_folder.expect_call("close_async");

        monitor.start_monitoring.begin(
            NONE, test_cancellable, this.async_completion
        );
        monitor.start_monitoring.end(async_result());

        // Process all of the async tasks arising from the open
        while (this.main_loop.pending()) {
            this.main_loop.iteration(true);
        }

        monitor.stop_monitoring.begin(
            test_cancellable, this.async_completion
        );
        monitor.stop_monitoring.end(async_result());

        assert_true(saw_scan_started, "scan_started not fired");
        assert_true(saw_scan_completed, "scan_completed not fired");

        this.base_folder.assert_expectations();
    }

    public void open_error() throws Error {
        ConversationMonitor monitor = new ConversationMonitor(
            this.base_folder, Email.Field.NONE, 10
        );

        ValaUnit.ExpectedCall open = this.base_folder
            .expect_call("open_async")
            .throws(new EngineError.SERVER_UNAVAILABLE("Mock error"));

        monitor.start_monitoring.begin(
            NONE, null, this.async_completion
        );
        try {
            monitor.start_monitoring.end(async_result());
            assert_not_reached();
        } catch (Error err) {
            assert_error(open.throw_error, err);
        }

        assert_false(monitor.is_monitoring, "is monitoring");

        this.base_folder.assert_expectations();
    }

    public void close_during_open_error() throws GLib.Error {
        ConversationMonitor monitor = new ConversationMonitor(
            this.base_folder, Email.Field.NONE, 10
        );

        ValaUnit.ExpectedCall open = this.base_folder
            .expect_call("open_async")
            .async_call(PAUSE)
            .throws(new GLib.IOError.CANCELLED("Mock error"));
        this.base_folder
            .expect_call("close_async")
            .throws(new EngineError.ALREADY_CLOSED("Mock error"));

        var start_waiter = new ValaUnit.AsyncResultWaiter(this.main_loop);
        monitor.start_monitoring.begin(NONE, null, start_waiter.async_completion);

        var stop_waiter = new ValaUnit.AsyncResultWaiter(this.main_loop);
        monitor.stop_monitoring.begin(null, stop_waiter.async_completion);

        open.async_resume();
        try {
            monitor.start_monitoring.end(start_waiter.async_result());
            assert_not_reached();
        } catch (GLib.Error err) {
            assert_error(open.throw_error, err);
        }

        // base_folder.close_async should not be called, so should not
        // throw an error
        monitor.stop_monitoring.end(stop_waiter.async_result());
    }

    public void close_after_open_error() throws GLib.Error {
        ConversationMonitor monitor = new ConversationMonitor(
            this.base_folder, Email.Field.NONE, 10
        );

        ValaUnit.ExpectedCall open = this.base_folder
            .expect_call("open_async")
            .throws(new EngineError.SERVER_UNAVAILABLE("Mock error"));
        this.base_folder
            .expect_call("close_async")
            .throws(new EngineError.ALREADY_CLOSED("Mock error"));

        monitor.start_monitoring.begin(NONE, null, this.async_completion);
        try {
            monitor.start_monitoring.end(async_result());
            assert_not_reached();
        } catch (GLib.Error err) {
            assert_error(open.throw_error, err);
        }

        // base_folder.close_async should not be called, so should not
        // throw an error
        monitor.stop_monitoring.begin(null, this.async_completion);
        monitor.stop_monitoring.end(async_result());
    }

    public void load_single_message() throws Error {
        Email e1 = setup_email(1);

        Gee.MultiMap<EmailIdentifier,FolderPath> paths =
            new Gee.HashMultiMap<EmailIdentifier,FolderPath>();
        paths.set(e1.id, this.base_folder.path);

        ConversationMonitor monitor = setup_monitor({e1}, paths);

        assert_equal<int?>(monitor.size, 1, "Conversation count");
        assert_non_null(monitor.window_lowest, "Lowest window id");
        assert_equal(monitor.window_lowest, e1.id, "Lowest window id");

        Conversation c1 = Collection.first(monitor.read_only_view);
        assert_equal(e1, c1.get_email_by_id(e1.id), "Email not present in conversation");
    }

    public void load_multiple_messages() throws Error {
        Email e1 = setup_email(1, null);
        Email e2 = setup_email(2, null);
        Email e3 = setup_email(3, null);

        Gee.MultiMap<EmailIdentifier,FolderPath> paths =
            new Gee.HashMultiMap<EmailIdentifier,FolderPath>();
        paths.set(e1.id, this.base_folder.path);
        paths.set(e2.id, this.base_folder.path);
        paths.set(e3.id, this.base_folder.path);

        ConversationMonitor monitor = setup_monitor({e3, e2, e1}, paths);

        assert_equal<int?>(monitor.size, 3, "Conversation count");
        assert_non_null(monitor.window_lowest, "Lowest window id");
        assert_equal(monitor.window_lowest, e1.id, "Lowest window id");
    }

    public void load_related_message() throws Error {
        Email e1 = setup_email(1);
        Email e2 = setup_email(2, e1);

        Gee.MultiMap<EmailIdentifier,FolderPath> paths =
            new Gee.HashMultiMap<EmailIdentifier,FolderPath>();
        paths.set(e1.id, this.other_folder.path);
        paths.set(e2.id, this.base_folder.path);

        Gee.MultiMap<Email,FolderPath> related_paths =
            new Gee.HashMultiMap<Email,FolderPath>();
        related_paths.set(e1, this.other_folder.path);
        related_paths.set(e2, this.base_folder.path);

        ConversationMonitor monitor = setup_monitor({e2}, paths, {related_paths});

        assert_equal<int?>(monitor.size, 1, "Conversation count");
        assert_non_null(monitor.window_lowest, "Lowest window id");
        assert_equal(monitor.window_lowest, e2.id, "Lowest window id");

        Conversation c1 = Collection.first(monitor.read_only_view);
        assert_equal(c1.get_email_by_id(e1.id), e1, "Related email not present in conversation");
        assert_equal(c1.get_email_by_id(e2.id), e2, "In folder not present in conversation");
    }

    public void base_folder_message_appended() throws Error {
        Email e1 = setup_email(1);

        Gee.MultiMap<EmailIdentifier,FolderPath> paths =
            new Gee.HashMultiMap<EmailIdentifier,FolderPath>();
        paths.set(e1.id, this.base_folder.path);

        ConversationMonitor monitor = setup_monitor();
        assert_equal<int?>(monitor.size, 0, "Initial conversation count");

        this.base_folder.expect_call("list_email_by_sparse_id_async")
            .returns_object(new Gee.ArrayList<Email>.wrap({e1}));

        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("local_search_message_id_async");

        this.account.expect_call("get_containing_folders_async")
            .returns_object(paths);

        this.base_folder.email_appended(new Gee.ArrayList<EmailIdentifier>.wrap({e1.id}));

        wait_for_signal(monitor, "conversations-added");
        this.base_folder.assert_expectations();
        this.account.assert_expectations();

        assert_equal<int?>(monitor.size, 1, "Conversation count");
    }

    public void base_folder_message_removed() throws Error {
        Email e1 = setup_email(1);
        Email e2 = setup_email(2, e1);
        Email e3 = setup_email(3);

        Gee.MultiMap<EmailIdentifier,FolderPath> paths =
            new Gee.HashMultiMap<EmailIdentifier,FolderPath>();
        paths.set(e1.id, this.other_folder.path);
        paths.set(e2.id, this.base_folder.path);
        paths.set(e3.id, this.base_folder.path);

        Gee.MultiMap<Email,FolderPath> e2_related_paths =
            new Gee.HashMultiMap<Email,FolderPath>();
        e2_related_paths.set(e1, this.other_folder.path);
        e2_related_paths.set(e2, this.base_folder.path);

        ConversationMonitor monitor = setup_monitor(
            {e3, e2}, paths, {null, e2_related_paths}
        );
        assert_equal<int?>(monitor.size, 2, "Initial conversation count");
        assert_equal(monitor.window_lowest, e2.id, "Lowest window id");

        this.base_folder.email_removed(new Gee.ArrayList<EmailIdentifier>.wrap({e2.id}));
        wait_for_signal(monitor, "conversations-removed");
        assert_equal<int?>(monitor.size, 1, "Conversation count");
        assert_equal(monitor.window_lowest, e3.id, "Lowest window id");

        this.base_folder.email_removed(new Gee.ArrayList<EmailIdentifier>.wrap({e3.id}));
        wait_for_signal(monitor, "conversations-removed");
        assert_equal<int?>(monitor.size, 0, "Conversation count");
        assert_null(monitor.window_lowest, "Lowest window id");

        // Close the monitor to cancel the final load so it does not
        // error out during later tests
        this.base_folder.expect_call("close_async");
        monitor.stop_monitoring.begin(
            null, this.async_completion
        );
        monitor.stop_monitoring.end(async_result());
    }

    public void external_folder_message_appended() throws Error {
        Email e1 = setup_email(1);
        Email e2 = setup_email(2, e1);
        Email e3 = setup_email(3, e1);

        Gee.MultiMap<EmailIdentifier,FolderPath> paths =
            new Gee.HashMultiMap<EmailIdentifier,FolderPath>();
        paths.set(e1.id, this.base_folder.path);
        paths.set(e2.id, this.base_folder.path);
        paths.set(e3.id, this.other_folder.path);

        Gee.MultiMap<Email,FolderPath> related_paths =
            new Gee.HashMultiMap<Email,FolderPath>();
        related_paths.set(e1, this.base_folder.path);
        related_paths.set(e3, this.other_folder.path);

        ConversationMonitor monitor = setup_monitor({e1}, paths);
        assert_equal<int?>(monitor.size, 1, "Initial conversation count");

        this.other_folder.expect_call("open_async");
        this.other_folder.expect_call("list_email_by_sparse_id_async")
            .returns_object(new Gee.ArrayList<Email>.wrap({e3}));
        this.other_folder.expect_call("list_email_by_sparse_id_async")
            .returns_object(new Gee.ArrayList<Email>.wrap({e3}));
        this.other_folder.expect_call("close_async");

        // ExternalAppendOperation's blacklist check
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");

        /////////////////////////////////////////////////////////
        // First call to expand_conversations_async for e3's refs

        // LocalSearchOperationAppendOperation's blacklist check
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");

        // Search for e1's ref
        this.account.expect_call("local_search_message_id_async")
            .returns_object(related_paths);

        // Search for e2's ref
        this.account.expect_call("local_search_message_id_async");

        //////////////////////////////////////////////////////////
        // Second call to expand_conversations_async for e1's refs

        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("local_search_message_id_async");

        // Finally, the call to process_email_complete_async

        this.account.expect_call("get_containing_folders_async")
            .returns_object(paths);

        // Should not be added, since it's actually in the base folder
        this.account.email_appended(
            this.base_folder,
            new Gee.ArrayList<EmailIdentifier>.wrap({e2.id})
        );

        // Should be added, since it's an external message
        this.account.email_appended(
            this.other_folder,
            new Gee.ArrayList<EmailIdentifier>.wrap({e3.id})
        );

        wait_for_signal(monitor, "conversations-added");
        this.base_folder.assert_expectations();
        this.other_folder.assert_expectations();
        this.account.assert_expectations();

        assert_equal<int?>(monitor.size, 1, "Conversation count");

        Conversation c1 = Collection.first(monitor.read_only_view);
        assert_equal<int?>(c1.get_count(), 2, "Conversation message count");
        assert_equal(c1.get_email_by_id(e3.id), e3,
                     "Appended email not present in conversation");
    }

    public void conversation_marked_as_deleted() throws Error {
        Email e1 = setup_email(1);

        Gee.MultiMap<EmailIdentifier,FolderPath> paths =
            new Gee.HashMultiMap<EmailIdentifier,FolderPath>();
        paths.set(e1.id, this.base_folder.path);

        ConversationMonitor monitor = setup_monitor({e1}, paths);
        assert_equal<int?>(monitor.size, 1, "Conversation count");

        // Mark message as deleted
        Gee.HashMap<EmailIdentifier,EmailFlags> flags_changed =
            new Gee.HashMap<EmailIdentifier,EmailFlags>();
        flags_changed.set(e1.id, new EmailFlags.with(EmailFlags.DELETED));
        this.account.email_flags_changed(this.base_folder, flags_changed);

        this.base_folder.expect_call("list_email_by_sparse_id_async");
        this.base_folder.expect_call("list_email_by_id_async");

        wait_for_signal(monitor, "email-flags-changed");

        assert_equal<int?>(
            monitor.size, 0,
            "Conversation count should now be zero after being marked deleted."
        );
    }

    private Email setup_email(int id, Email? references = null) {
        Email email = new Email(new Mock.EmailIdentifer(id));
        DateTime now = new DateTime.now_local();
        Geary.RFC822.MessageID mid = new Geary.RFC822.MessageID(
            "test%d@localhost".printf(id)
        );

        Geary.RFC822.MessageIDList refs_list = null;
        if (references != null) {
            refs_list = new Geary.RFC822.MessageIDList.single(
                references.message_id
            );
        }
        email.set_send_date(new RFC822.Date(now));
        email.set_email_properties(new Mock.EmailProperties(now));
        email.set_full_references(mid, null, refs_list);
        return email;
    }

    private ConversationMonitor
        setup_monitor(Email[] base_folder_email = {},
                      Gee.MultiMap<EmailIdentifier,FolderPath>? paths = null,
                      Gee.MultiMap<Email,FolderPath>[] related_paths = {})
        throws Error {
        ConversationMonitor monitor = new ConversationMonitor(
            this.base_folder, Email.Field.NONE, 10
        );
        Cancellable test_cancellable = new Cancellable();

        /*
         * The process for loading messages looks roughly like this:
         * - load_by_id_async
         *   - base_folder.list_email_by_id_async
         *   - process_email_async
         *     - gets all related messages from listing
         *     - expand_conversations_async
         *       - get_search_folder_blacklist (i.e. account.get_special_folder × 3)
         *       - foreach related: account.local_search_message_id_async
         *       - process_email_async
         *         - process_email_complete_async
         *           - get_containing_folders_async
         */

        this.base_folder.expect_call("open_async");
        ValaUnit.ExpectedCall list_call = this.base_folder
            .expect_call("list_email_by_id_async")
            .returns_object(new Gee.ArrayList<Email>.wrap(base_folder_email));

        if (base_folder_email.length > 0) {
            // expand_conversations_async calls
            // Account:get_special_folder() in
            // get_search_folder_blacklist, and the default
            // implementation of that calls get_special_folder.
            this.account.expect_call("get_special_folder");
            this.account.expect_call("get_special_folder");
            this.account.expect_call("get_special_folder");

            Gee.List<RFC822.MessageID> base_email_ids =
                new Gee.ArrayList<RFC822.MessageID>();
            foreach (Email base_email in base_folder_email) {
                base_email_ids.add(base_email.message_id);
            }

            int base_i = 0;
            bool has_related = (
                base_folder_email.length == related_paths.length
            );
            bool found_related = false;
            Gee.Set<RFC822.MessageID> seen_ids = new Gee.HashSet<RFC822.MessageID>();
            foreach (Email base_email in base_folder_email) {
                ValaUnit.ExpectedCall call =
                    this.account.expect_call("local_search_message_id_async");
                seen_ids.add(base_email.message_id);
                if (has_related && related_paths[base_i] != null) {
                    call.returns_object(related_paths[base_i++]);
                    found_related = true;
                }

                foreach (RFC822.MessageID ancestor in base_email.get_ancestors()) {
                    if (!seen_ids.contains(ancestor) && !base_email_ids.contains(ancestor)) {
                        this.account.expect_call("local_search_message_id_async");
                        seen_ids.add(ancestor);
                    }
                }
            }

            // Second call to expand_conversations_async will be made
            // if any related were loaded
            if (found_related) {
                this.account.expect_call("get_special_folder");
                this.account.expect_call("get_special_folder");
                this.account.expect_call("get_special_folder");

                seen_ids.clear();
                foreach (Gee.MultiMap<Email,FolderPath> related in related_paths) {
                    if (related != null) {
                        foreach (Email email in related.get_keys()) {
                            if (!base_email_ids.contains(email.message_id)) {
                                foreach (RFC822.MessageID ancestor in email.get_ancestors()) {
                                    if (!seen_ids.contains(ancestor)) {
                                        this.account.expect_call("local_search_message_id_async");
                                        seen_ids.add(ancestor);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ValaUnit.ExpectedCall contains =
                this.account.expect_call("get_containing_folders_async");
            if (paths != null) {
                contains.returns_object(paths);
            }
        }

        monitor.start_monitoring.begin(
            NONE, test_cancellable, this.async_completion
        );
        monitor.start_monitoring.end(async_result());

        if (base_folder_email.length == 0) {
            wait_for_call(list_call);
        } else {
            wait_for_signal(monitor, "conversations-added");
        }

        this.base_folder.assert_expectations();
        this.account.assert_expectations();

        return monitor;
    }

}
