/*
 * Copyright 2017-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.App.ConversationTest : TestCase {


    Conversation? test = null;
    Folder? base_folder = null;
    FolderRoot? folder_root = null;


    public ConversationTest() {
        base("Geary.App.ConversationTest");
        add_test("add_basic", add_basic);
        add_test("add_duplicate", add_duplicate);
        add_test("add_multipath", add_multipath);
        add_test("remove_basic", remove_basic);
        add_test("remove_nonexistent", remove_nonexistent);
        add_test("get_emails", get_emails);
        add_test("get_emails_by_location", get_emails_by_location);
        add_test("get_emails_blacklist", get_emails_blacklist);
        add_test("get_emails_marked_for_deletion", get_emails_marked_for_deletion);
        add_test("count_email_in_folder", count_email_in_folder);
    }

    public override void set_up() {
        this.folder_root = new FolderRoot("#test", false);
        this.base_folder = new Mock.Folder(
            null,
            null,
            this.folder_root.get_child("test"),
            NONE,
            null
        );
        this.test = new Conversation(this.base_folder);
    }

    public override void tear_down() {
        this.test = null;
        this.folder_root = null;
        this.base_folder = null;
    }

    public void add_basic() throws Error {
        Geary.Email e1 = setup_email(1);
        Geary.Email e2 = setup_email(2);
        uint appended = 0;
        this.test.appended.connect(() => {
                appended++;
            });

        assert(this.test.add(e1, singleton(this.base_folder.path)) == true);
        assert(this.test.is_in_base_folder(e1.id) == true);
        assert(this.test.get_folder_count(e1.id) == 1);
        assert(appended == 1);
        assert(this.test.get_count() == 1);

        assert(this.test.add(e2, singleton(this.base_folder.path)) == true);
        assert(this.test.is_in_base_folder(e2.id) == true);
        assert(this.test.get_folder_count(e2.id) == 1);
        assert(appended == 2);
        assert(this.test.get_count() == 2);
    }

    public void add_duplicate() throws Error {
        Geary.Email e1 = setup_email(1);
        uint appended = 0;
        this.test.appended.connect(() => {
                appended++;
            });

        assert(this.test.add(e1, singleton(this.base_folder.path)) == true);
        assert(appended == 1);
        assert(this.test.get_count() == 1);

        assert(this.test.add(e1, singleton(this.base_folder.path)) == false);
        assert(appended == 1);
        assert(this.test.get_count() == 1);
    }

    public void add_multipath() throws Error {
        Geary.Email e1 = setup_email(1);
        this.test.add(e1, singleton(this.base_folder.path));

        Geary.Email e2 = setup_email(2);
        this.test.add(e2, singleton(this.base_folder.path));

        FolderPath other_path = this.folder_root.get_child("other");
        Gee.LinkedList<FolderPath> other_paths = new Gee.LinkedList<FolderPath>();
        other_paths.add(other_path);

        assert(this.test.add(e1, other_paths) == false);
        assert(this.test.is_in_base_folder(e1.id) == true);
        assert(this.test.get_folder_count(e1.id) == 2);

        assert(this.test.is_in_base_folder(e2.id) == true);
        assert(this.test.get_folder_count(e2.id) == 1);

        this.test.remove_path(e1.id, other_path);
        assert(this.test.is_in_base_folder(e1.id) == true);
        assert(this.test.get_folder_count(e1.id) == 1);
    }

    public void remove_basic() throws Error {
        Geary.Email e1 = setup_email(1);
        this.test.add(e1, singleton(this.base_folder.path));

        Geary.Email e2 = setup_email(2);
        this.test.add(e2, singleton(this.base_folder.path));

        uint trimmed = 0;
        this.test.trimmed.connect(() => {
                trimmed++;
            });

        Gee.Set<RFC822.MessageID>? removed = this.test.remove(e1);
        assert(removed != null);
        assert(removed.size == 1);
        assert(removed.contains(e1.message_id));
        assert(trimmed == 1);
        assert(this.test.get_count() == 1);

        removed = this.test.remove(e2);
        assert(removed != null);
        assert(removed.size == 1);
        assert(removed.contains(e2.message_id));
        assert(trimmed == 2);
        assert(this.test.get_count() == 0);
    }

    public void remove_nonexistent() throws Error {
        Geary.Email e1 = setup_email(1);
        Geary.Email e2 = setup_email(2);

        uint trimmed = 0;
        this.test.trimmed.connect(() => {
                trimmed++;
            });

        assert(this.test.remove(e2) == null);
        assert(trimmed == 0);
        assert(this.test.get_count() == 0);

        this.test.add(e1, singleton(this.base_folder.path));

        assert(this.test.remove(e2) == null);
        assert(trimmed == 0);
        assert(this.test.get_count() == 1);
    }

    public void get_emails() throws GLib.Error {
        Geary.Email e1 = setup_email(1);
        this.test.add(e1, singleton(this.base_folder.path));

        FolderPath other_path = this.folder_root.get_child("other");
        Geary.Email e2 = setup_email(2);
        this.test.add(e2, singleton(other_path));

        assert_collection(
            this.test.get_emails(Conversation.Ordering.NONE)
        ).size(2);
    }

    public void get_emails_by_location() throws GLib.Error {
        Geary.Email e1 = setup_email(1);
        this.test.add(e1, singleton(this.base_folder.path));

        FolderPath other_path = this.folder_root.get_child("other");
        Geary.Email e2 = setup_email(2);
        this.test.add(e2, singleton(other_path));

        assert_collection(
            this.test.get_emails(NONE, IN_FOLDER),
            "Unexpected in-folder element"
        ).size(1).contains(e1);

        assert_collection(
            this.test.get_emails(NONE, OUT_OF_FOLDER),
            "Unexpected out-of-folder element"
        ).size(1).contains(e2);
    }

    public void get_emails_blacklist() throws GLib.Error {
        Geary.Email e1 = setup_email(1);
        this.test.add(e1, singleton(this.base_folder.path));

        FolderPath other_path = this.folder_root.get_child("other");
        Geary.Email e2 = setup_email(2);
        this.test.add(e2, singleton(other_path));

        Gee.Collection<FolderPath> blacklist = new Gee.ArrayList<FolderPath>();

        blacklist.add(other_path);
        assert_collection(
            this.test.get_emails(NONE, ANYWHERE, blacklist),
            "Unexpected other blacklist element"
        ).size(1).contains(e1);

        blacklist.clear();
        blacklist.add(this.base_folder.path);
        assert_collection(
            this.test.get_emails(NONE, ANYWHERE, blacklist),
            "Unexpected other blacklist element"
        ).size(1).contains(e2);
    }

    public void get_emails_marked_for_deletion() throws GLib.Error {
        Geary.Email e1 = setup_email(1);
        e1.set_flags(new Geary.EmailFlags.with(Geary.EmailFlags.DELETED));
        this.test.add(e1, singleton(this.base_folder.path));

        assert_collection(
            this.test.get_emails(NONE, ANYWHERE),
            "Message marked for deletion still present in conversation"
        ).is_empty();
    }

    public void count_email_in_folder() throws GLib.Error {
        Geary.Email e1 = setup_email(1);
        this.test.add(e1, singleton(this.base_folder.path));

        assert_equal<uint?>(
            this.test.get_count_in_folder(this.base_folder.path),
            1,
            "In-folder count"
        );
        assert_equal<uint?>(
            this.test.get_count_in_folder(this.folder_root.get_child("other")),
            0,
            "Out-folder count"
        );
    }

    private Gee.Collection<E> singleton<E>(E element) {
        Gee.LinkedList<E> collection = new Gee.LinkedList<E>();
        collection.add(element);
        return collection;
    }


    private Email setup_email(int id) {
        Email email = new Email(new Mock.EmailIdentifer(id));
        DateTime now = new DateTime.now_local();
        Geary.RFC822.MessageID mid = new Geary.RFC822.MessageID(
            "test%d@localhost".printf(id)
        );
        email.set_full_references(mid, null, null);
        email.set_email_properties(new Mock.EmailProperties(now));
        email.set_send_date(new RFC822.Date(now));
        return email;
    }

}
