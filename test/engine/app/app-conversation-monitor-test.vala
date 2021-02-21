/*
 * Copyright © 2018-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Geary.App.ConversationMonitorTest : TestCase {


    AccountInformation? account_info = null;
    Mock.Account? account = null;
    Folder.Root? folder_root = null;
    Mock.RemoteFolder? base_folder = null;
    Mock.Folder? other_folder = null;


    public ConversationMonitorTest() {
        base("Geary.App.ConversationMonitorTest");
        add_test(
            "start_stop_monitoring_remote_not_started",
            start_stop_monitoring_remote_not_started
        );
        add_test(
            "start_stop_monitoring_remote_already_started",
            start_stop_monitoring_remote_already_started
        );
        add_test(
            "start_stop_monitoring_local",
            start_stop_monitoring_local
        );
        add_test("load_single_message", load_single_message);
        add_test("load_multiple_messages", load_multiple_messages);
        add_test("load_related_message", load_related_message);
        add_test("base_folder_message_appended", base_folder_message_appended);
        add_test("base_folder_message_removed", base_folder_message_removed);
        add_test("external_folder_message_appended", external_folder_message_appended);
        add_test("conversation_marked_as_deleted", conversation_marked_as_deleted);
        add_test("incomplete_base_folder", incomplete_base_folder);
        add_test("incomplete_external_folder", incomplete_external_folder);
    }

    public override void set_up() {
        this.account_info = new AccountInformation(
            "account_01",
            ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new RFC822.MailboxAddress(null, "test1@example.com")
        );
        this.account = new Mock.Account(this.account_info);
        this.folder_root = new Folder.Root("#test", false);
        this.base_folder = new Mock.RemoteFolder(
            this.account,
            null,
            this.folder_root.get_child("base"),
            NONE,
            null,
            false,
            false
        );
        this.other_folder = new Mock.Folder(
            this.account,
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

    public void start_stop_monitoring_remote_not_started() throws GLib.Error {
        var test_article = new Mock.RemoteFolder(
            this.account,
            null,
            this.folder_root.get_child("base"),
            NONE,
            null,
            false,
            false
        );
        ConversationMonitor monitor = new ConversationMonitor(
            test_article, Email.Field.NONE, 10
        );
        Cancellable test_cancellable = new Cancellable();

        bool saw_scan_started = false;
        bool saw_scan_completed = false;
        monitor.scan_started.connect(() => { saw_scan_started = true; });
        monitor.scan_completed.connect(() => { saw_scan_completed = true; });

        test_article.expect_call("start_monitoring");
        test_article.expect_call("list_email_range_by_id")
            .returns_object(new Gee.ArrayList<Email>());
        test_article.expect_call("stop_monitoring");

        monitor.start_monitoring.begin(
            test_cancellable, this.async_completion
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

        test_article.assert_expectations();
    }

    public void start_stop_monitoring_remote_already_started()
        throws GLib.Error {
        var test_article = new Mock.RemoteFolder(
            this.account,
            null,
            this.folder_root.get_child("base"),
            NONE,
            null,
            true,
            false
        );
        ConversationMonitor monitor = new ConversationMonitor(
            test_article, Email.Field.NONE, 10
        );
        Cancellable test_cancellable = new Cancellable();

        bool saw_scan_started = false;
        bool saw_scan_completed = false;
        monitor.scan_started.connect(() => { saw_scan_started = true; });
        monitor.scan_completed.connect(() => { saw_scan_completed = true; });

        test_article.expect_call("list_email_range_by_id")
            .returns_object(new Gee.ArrayList<Email>());

        monitor.start_monitoring.begin(
            test_cancellable, this.async_completion
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

        test_article.assert_expectations();
    }

    public void start_stop_monitoring_local()
        throws GLib.Error {
        var test_article = new Mock.Folder(
            this.account,
            this.folder_root.get_child("base"),
            NONE,
            null
        );
        ConversationMonitor monitor = new ConversationMonitor(
            test_article, Email.Field.NONE, 10
        );
        Cancellable test_cancellable = new Cancellable();

        bool saw_scan_started = false;
        bool saw_scan_completed = false;
        monitor.scan_started.connect(() => { saw_scan_started = true; });
        monitor.scan_completed.connect(() => { saw_scan_completed = true; });

        test_article.expect_call("list_email_range_by_id")
            .returns_object(new Gee.ArrayList<Email>());

        monitor.start_monitoring.begin(
            test_cancellable, this.async_completion
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

        test_article.assert_expectations();
    }

    public void load_single_message() throws Error {
        Email e1 = setup_email(1);

        Gee.MultiMap<EmailIdentifier,Folder.Path> paths =
            new Gee.HashMultiMap<EmailIdentifier,Folder.Path>();
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

        Gee.MultiMap<EmailIdentifier,Folder.Path> paths =
            new Gee.HashMultiMap<EmailIdentifier,Folder.Path>();
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

        Gee.MultiMap<EmailIdentifier,Folder.Path> paths =
            new Gee.HashMultiMap<EmailIdentifier,Folder.Path>();
        paths.set(e1.id, this.other_folder.path);
        paths.set(e2.id, this.base_folder.path);

        Gee.MultiMap<Email,Folder.Path> related_paths =
            new Gee.HashMultiMap<Email,Folder.Path>();
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

        Gee.MultiMap<EmailIdentifier,Folder.Path> paths =
            new Gee.HashMultiMap<EmailIdentifier,Folder.Path>();
        paths.set(e1.id, this.base_folder.path);

        ConversationMonitor monitor = setup_monitor();
        assert_equal<int?>(monitor.size, 0, "Initial conversation count");

        this.base_folder.expect_call(
            "get_multiple_email_by_id"
        ).returns_object(
            Collection.single_set(e1)
        );

        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("local_search_message_id_async");

        this.account.expect_call("get_containing_folders_async")
            .returns_object(paths);

        this.base_folder.email_appended(
            new Gee.ArrayList<EmailIdentifier>.wrap({e1.id})
        );

        wait_for_signal(monitor, "conversations-added");
        this.base_folder.assert_expectations();
        this.account.assert_expectations();

        assert_equal<int?>(monitor.size, 1, "Conversation count");
    }

    public void base_folder_message_removed() throws Error {
        Email e1 = setup_email(1);
        Email e2 = setup_email(2, e1);
        Email e3 = setup_email(3);

        Gee.MultiMap<EmailIdentifier,Folder.Path> paths =
            new Gee.HashMultiMap<EmailIdentifier,Folder.Path>();
        paths.set(e1.id, this.other_folder.path);
        paths.set(e2.id, this.base_folder.path);
        paths.set(e3.id, this.base_folder.path);

        Gee.MultiMap<Email,Folder.Path> e2_related_paths =
            new Gee.HashMultiMap<Email,Folder.Path>();
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
        this.base_folder.expect_call("stop_monitoring");
        monitor.stop_monitoring.begin(
            null, this.async_completion
        );
        monitor.stop_monitoring.end(async_result());
    }

    public void external_folder_message_appended() throws Error {
        Email e1 = setup_email(1);
        Email e2 = setup_email(2, e1);
        Email e3 = setup_email(3, e1);

        Gee.MultiMap<EmailIdentifier,Folder.Path> paths =
            new Gee.HashMultiMap<EmailIdentifier,Folder.Path>();
        paths.set(e1.id, this.base_folder.path);
        paths.set(e2.id, this.base_folder.path);
        paths.set(e3.id, this.other_folder.path);

        Gee.MultiMap<Email,Folder.Path> related_paths =
            new Gee.HashMultiMap<Email,Folder.Path>();
        related_paths.set(e1, this.base_folder.path);
        related_paths.set(e3, this.other_folder.path);

        ConversationMonitor monitor = setup_monitor({e1}, paths);
        assert_equal<int?>(monitor.size, 1, "Initial conversation count");

        // ExternalAppendOperation's blacklist check
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");

        this.account.expect_call(
            "get_multiple_email_by_id"
        ).returns_object(
            Collection.single_set(e3)
        );

        this.account.expect_call(
            "get_multiple_email_by_id"
        ).returns_object(
            Collection.single_set(e3)
        );

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

        // Should be added, since it's an external message
        this.account.email_appended_to_folder(
            new Gee.ArrayList<EmailIdentifier>.wrap({e3.id}),
            this.other_folder
        );

        wait_for_signal(monitor, "conversations-added");
        this.base_folder.assert_expectations();
        this.account.assert_expectations();

        assert_equal<int?>(monitor.size, 1, "Conversation count");

        Conversation c1 = Collection.first(monitor.read_only_view);
        assert_equal<int?>(c1.get_count(), 2, "Conversation message count");
        assert_equal(c1.get_email_by_id(e3.id), e3,
                     "Appended email not present in conversation");
    }

    public void conversation_marked_as_deleted() throws Error {
        Email e1 = setup_email(1);

        Gee.MultiMap<EmailIdentifier,Folder.Path> paths =
            new Gee.HashMultiMap<EmailIdentifier,Folder.Path>();
        paths.set(e1.id, this.base_folder.path);

        ConversationMonitor monitor = setup_monitor({e1}, paths);
        assert_equal<int?>(monitor.size, 1, "Conversation count");

        // Mark message as deleted
        Gee.HashMap<EmailIdentifier,EmailFlags> flags_changed =
            new Gee.HashMap<EmailIdentifier,EmailFlags>();
        flags_changed.set(e1.id, new EmailFlags.with(EmailFlags.DELETED));
        this.account.email_flags_changed_in_folder(
            flags_changed,
            this.base_folder
        );

        this.base_folder.expect_call("get_multiple_email_by_id");
        this.base_folder.expect_call("list_email_range_by_id")
            .returns_object(new Gee.ArrayList<Email>());

        wait_for_signal(monitor, "email-flags-changed");

        assert_equal<int?>(
            monitor.size, 0,
            "Conversation count should now be zero after being marked deleted."
        );
    }

    public void incomplete_base_folder() throws Error {
        var incomplete = new Email(new Mock.EmailIdentifer(1));
        var complete = setup_email(1);

        var paths = new Gee.HashMultiMap<EmailIdentifier,Folder.Path>();
        paths.set(incomplete.id, this.base_folder.path);

        var monitor = new ConversationMonitor(this.base_folder, NONE, 10);

        this.base_folder.expect_call("start_monitoring");
        ValaUnit.ExpectedCall incomplete_list_call = this.base_folder
            .expect_call("list_email_range_by_id")
            .returns_object(Collection.single(incomplete));

        monitor.start_monitoring.begin(null, this.async_completion);
        monitor.start_monitoring.end(async_result());
        wait_for_call(incomplete_list_call);
        assert_equal<int?>(monitor.size, 0, "incomplete count");

        // Process all of the async tasks arising from the open
        while (this.main_loop.pending()) {
            this.main_loop.iteration(true);
        }

        this.base_folder
            .expect_call("get_multiple_email_by_id")
            .returns_object(Collection.single(complete));
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("local_search_message_id_async");
        this.account.expect_call("get_containing_folders_async")
            .returns_object(paths);

        this.account.email_complete(Collection.single(complete.id));

        wait_for_signal(monitor, "conversations-added");
        assert_equal<int?>(monitor.size, 1, "complete count");

        this.base_folder.assert_expectations();
        this.account.assert_expectations();
    }

    public void incomplete_external_folder() throws Error {
        var in_folder = setup_email(1);
        var incomplete_external = new Email(new Mock.EmailIdentifer(2));
        var complete_external = setup_email(2, in_folder);

        var in_folder_paths = new Gee.HashMultiMap<EmailIdentifier,Folder.Path>();
        in_folder_paths.set(in_folder.id, this.base_folder.path);

        var external_paths = new Gee.HashMultiMap<EmailIdentifier,Folder.Path>();
        external_paths.set(complete_external.id, this.other_folder.path);

        var related_paths = new Gee.HashMultiMap<Email,Folder.Path>();
        related_paths.set(in_folder, this.base_folder.path);
        related_paths.set(complete_external, this.other_folder.path);

        var monitor = setup_monitor({in_folder}, in_folder_paths);

        // initial call with incomplete email

        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");

        var initial_incomplete_load = this.account
            .expect_call("get_multiple_email_by_id")
            .returns_object(Collection.single(incomplete_external));

        // Should not get added, since it's incomplete
        this.account.email_appended_to_folder(
            Collection.single(incomplete_external.id),
            this.other_folder
        );

        wait_for_call(initial_incomplete_load);
        while (this.main_loop.pending()) {
            this.main_loop.iteration(true);
        }

        assert_equal<int?>(monitor.size, 1, "incomplete count");
        var c1 = Collection.first(monitor.read_only_view);
        assert_equal<int?>(c1.get_count(), 1, "incomplete conversation count");

        // email completed

        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");

        this.account
            .expect_call("get_multiple_email_by_id")
            .returns_object(Collection.single(complete_external));

        this.account
            .expect_call("get_multiple_email_by_id")
            .returns_object(Collection.single(complete_external));

        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");

        this.account.expect_call("local_search_message_id_async")
            .returns_object(related_paths);
        this.account.expect_call("local_search_message_id_async");

        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");
        this.account.expect_call("get_special_folder");

        this.account.expect_call("local_search_message_id_async");
        this.account.expect_call("get_containing_folders_async")
            .returns_object(external_paths);

        this.account.email_complete(Collection.single(complete_external.id));

        wait_for_signal(monitor, "conversation-appended");
        while (this.main_loop.pending()) {
            this.main_loop.iteration(true);
        }

        assert_equal<int?>(monitor.size, 1, "incomplete count");
        var c2 = Collection.first(monitor.read_only_view);
        assert_equal<int?>(c2.get_count(), 2, "incomplete conversation count");
        assert_equal(c2.get_email_by_id(complete_external.id), complete_external,
                     "completed email not present in conversation");
    }

    private Email setup_email(int id, Email? references = null) {
        Email email = new Email(new Mock.EmailIdentifer(id));

        DateTime now = new DateTime.now_local();
        email.set_send_date(new RFC822.Date(now));
        email.set_email_properties(new Mock.EmailProperties(now));

        Geary.RFC822.MessageID mid = new Geary.RFC822.MessageID(
            "test%d@localhost".printf(id)
        );
        Geary.RFC822.MessageIDList refs_list = null;
        if (references != null) {
            refs_list = new Geary.RFC822.MessageIDList.single(
                references.message_id
            );
        }
        email.set_full_references(mid, null, refs_list);

        email.set_flags(new EmailFlags());
        return email;
    }

    private ConversationMonitor
        setup_monitor(Email[] base_folder_email = {},
                      Gee.MultiMap<EmailIdentifier,Folder.Path>? paths = null,
                      Gee.MultiMap<Email,Folder.Path>[] related_paths = {})
        throws Error {
        ConversationMonitor monitor = new ConversationMonitor(
            this.base_folder, Email.Field.NONE, 10
        );
        Cancellable test_cancellable = new Cancellable();

        /*
         * The process for loading messages looks roughly like this:
         * - load_by_id_async
         *   - base_folder.list_email_range_by_id
         *   - process_email_async
         *     - gets all related messages from listing
         *     - expand_conversations_async
         *       - get_search_folder_blacklist (i.e. account.get_special_folder × 3)
         *       - foreach related: account.local_search_message_id_async
         *       - process_email_async
         *         - process_email_complete_async
         *           - get_containing_folders_async
         */

        this.base_folder.expect_call("start_monitoring");
        ValaUnit.ExpectedCall list_call = this.base_folder
            .expect_call("list_email_range_by_id")
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
                foreach (Gee.MultiMap<Email,Folder.Path> related in related_paths) {
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
            test_cancellable, this.async_completion
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
