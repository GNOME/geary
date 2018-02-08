/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.App.ConversationSetTest : Gee.TestCase {


    ConversationSet? test = null;
    Folder? base_folder = null;

    public ConversationSetTest() {
        base("Geary.App.ConversationSetTest");
        add_test("add_all_basic", add_all_basic);
        add_test("add_all_duplicate", add_all_duplicate);
        add_test("add_all_append_descendants", add_all_append_descendants);
        add_test("add_all_append_ancestors", add_all_append_ancestors);
        add_test("add_all_merge", add_all_merge);
        add_test("add_all_multi_path", add_all_multi_path);
        add_test("add_all_append_path", add_all_append_path);
        add_test("remove_all_removed", remove_all_removed);
        add_test("remove_all_trimmed", remove_all_trimmed);
        add_test("remove_all_remove_path", remove_all_remove_path);
    }

    public override void set_up() {
        this.test = new ConversationSet();
        this.base_folder = new MockFolder(
            null,
            null,
            new MockFolderRoot("test"),
            SpecialFolderType.NONE,
            null
        );
    }

    public void add_all_basic() {
        Email e1 = setup_email(1);
        Email e2 = setup_email(2);

        Gee.LinkedList<Email> emails = new Gee.LinkedList<Email>();
        emails.add(e1);
        emails.add(e2);

        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath> email_paths =
            new Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath>();
        email_paths.set(e1.id, this.base_folder.path);
        email_paths.set(e2.id, this.base_folder.path);

        Gee.Collection<Conversation>? added = null;
        Gee.MultiMap<Conversation,Email>? appended = null;
        Gee.Collection<Conversation>? removed = null;

        this.test.add_all_emails(
            emails, email_paths, this.base_folder,
            out added, out appended, out removed
        );

        assert(this.test.size == 2);
        assert(this.test.get_email_count() == 2);

        assert(added != null);
        assert(appended != null);
        assert(removed != null);

        // Work out which collection in the collection corresponds to which
        assert(added.size == 2);
        Conversation? c1 = null;
        Conversation? c2 = null;
        foreach (Conversation convo in added) {
            if (convo.get_email_by_id(e1.id) != null) {
                c1 = convo;
            } else if (convo.get_email_by_id(e2.id) != null) {
                c2 = convo;
            }
        }
        assert(c1 != null);
        assert(c2 != null);

        assert(appended.size == 0);
        assert(removed.is_empty);
    }

    public void add_all_duplicate() {
        Email e1 = setup_email(1);

        Gee.LinkedList<Email> emails = new Gee.LinkedList<Email>();
        emails.add(e1);
        emails.add(e1);

        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath> email_paths =
            new Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath>();
        email_paths.set(e1.id, this.base_folder.path);

        // Pass 1: Duplicate in same input collection

        Gee.Collection<Conversation>? added = null;
        Gee.MultiMap<Conversation,Email>? appended = null;
        Gee.Collection<Conversation>? removed = null;
        this.test.add_all_emails(
            emails, email_paths, this.base_folder,
            out added, out appended, out removed
        );

        assert(this.test.size == 1);
        assert(this.test.get_email_count() == 1);

        assert(added.size == 1);
        assert(Geary.Collection.get_first(added).get_email_by_id(e1.id) == e1);

        assert(appended.size == 0);
        assert(removed.is_empty);

        // Pass 2: Duplicate being re-added

        added = null;
        appended = null;
        removed = null;
        this.test.add_all_emails(
            emails, email_paths, this.base_folder,
            out added, out appended, out removed
        );

        assert(this.test.size == 1);
        assert(this.test.get_email_count() == 1);

        assert(added.is_empty);
        assert(appended.size == 0);
        assert(removed.is_empty);
    }

    public void add_all_append_descendants() {
        Email e1 = setup_email(1);
        Email e2 = setup_email(2, e1);

        // Pass 1: Append two at the same time

        Gee.LinkedList<Email> emails = new Gee.LinkedList<Email>();
        emails.add(e1);
        emails.add(e2);

        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath> email_paths =
            new Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath>();
        email_paths.set(e1.id, this.base_folder.path);
        email_paths.set(e2.id, new MockFolderRoot("other"));

        Gee.Collection<Conversation>? added = null;
        Gee.MultiMap<Conversation,Email>? appended = null;
        Gee.Collection<Conversation>? removed = null;
        this.test.add_all_emails(
            emails, email_paths, this.base_folder,
            out added, out appended, out removed
        );

        assert(this.test.size == 1);
        assert(this.test.get_email_count() == 2);

        assert(added.size == 1);

        Conversation convo1 = Geary.Collection.get_first(added);
        assert(convo1.get_email_by_id(e1.id) == e1);
        assert(convo1.get_email_by_id(e2.id) == e2);

        assert(appended.size == 0);
        assert(removed.is_empty);

        // Pass 2: Append one to an existing convo

        Email e3 = setup_email(3, e1);

        emails.clear();
        email_paths.clear();

        emails.add(e3);
        email_paths.set(e3.id, this.base_folder.path);

        added = null;
        appended = null;
        removed = null;
        this.test.add_all_emails(
            emails, email_paths, this.base_folder,
            out added, out appended, out removed
        );

        assert(this.test.size == 1);
        assert(this.test.get_email_count() == 3);

        assert(added.is_empty);

        assert(appended.size == 1);
        Conversation convo2 = Geary.Collection.get_first(appended.get_keys());
        assert(convo2.get_email_by_id(e1.id) == e1);
        assert(convo2.get_email_by_id(e2.id) == e2);
        assert(convo2.get_email_by_id(e3.id) == e3);

        assert(appended.contains(convo2) == true);
        assert(appended.get(convo2).contains(e1) != true);
        assert(appended.get(convo2).contains(e2) != true);
        assert(appended.get(convo2).contains(e3) == true);

        assert(removed.is_empty);
    }

    public void add_all_append_ancestors() {
        Email e1 = setup_email(1);
        Email e2 = setup_email(2, e1);

        add_email_to_test_set(e2);

        Gee.LinkedList<Email> emails = new Gee.LinkedList<Email>();
        emails.add(e1);

        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath> email_paths =
            new Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath>();
        email_paths.set(e1.id, this.base_folder.path);

        Gee.Collection<Conversation>? added = null;
        Gee.MultiMap<Conversation,Email>? appended = null;
        Gee.Collection<Conversation>? removed = null;
        this.test.add_all_emails(
            emails, email_paths, this.base_folder,
            out added, out appended, out removed
        );

        assert(this.test.size == 1);
        assert(this.test.get_email_count() == 2);

        assert(added.is_empty);

        assert(appended.size == 1);
        Conversation convo = Geary.Collection.get_first(appended.get_keys());
        assert(convo.get_email_by_id(e1.id) == e1);
        assert(convo.get_email_by_id(e2.id) == e2);

        assert(appended.contains(convo) == true);
        assert(appended.get(convo).contains(e1) == true);

        assert(removed.is_empty);
    }

    public void add_all_merge() {
        Email e1 = setup_email(1);
        add_email_to_test_set(e1);

        Email e2 = setup_email(2, e1);

        Email e3 = setup_email(3, e2);
        add_email_to_test_set(e3);

        assert(this.test.size == 2);
        assert(this.test.get_email_count() == 2);

        Conversation? c1 = this.test.get_by_email_identifier(e1.id);
        Conversation? c3 = this.test.get_by_email_identifier(e3.id);

        assert(c1 != null);
        assert(c3 != null);
        assert(c1 != c3);

        Gee.LinkedList<Email> emails = new Gee.LinkedList<Email>();
        emails.add(e2);

        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath> email_paths =
            new Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath>();
        email_paths.set(e2.id, this.base_folder.path);

        Gee.Collection<Conversation>? added = null;
        Gee.MultiMap<Conversation,Email>? appended = null;
        Gee.Collection<Conversation>? removed = null;
        this.test.add_all_emails(
            emails, email_paths, this.base_folder,
            out added, out appended, out removed
        );

        assert(this.test.size == 1);
        assert(this.test.get_email_count() == 3);

        Conversation? c2 = this.test.get_by_email_identifier(e2.id);
        assert(c2 != null);
        assert(c2.get_email_by_id(e1.id) == e1);
        assert(c2.get_email_by_id(e2.id) == e2);
        assert(c2.get_email_by_id(e3.id) == e3);

        // e2 might have been appended to e1's convo with e3, or vice
        // versa, depending on the gods of entropy.
        assert(c1 == c2 || c3 == c2);
        bool e1_won = (c1 == c2);

        assert(appended.size == 2);
        assert(appended.get(c2) != null);
        assert(appended.get(c2).size == 2);
        assert(appended.get(c2).contains(e2) == true);
        if (e1_won) {
            assert(appended.get(c2).contains(e3) == true);
        } else {
            assert(appended.get(c2).contains(e1) == true);
        }

        assert(added.is_empty);
        assert(removed.size == 1);
        if (e1_won) {
            assert(removed.contains(c3) == true);
        } else {
            assert(removed.contains(c1) == true);
        }

    }

    public void add_all_multi_path() {
        Email e1 = setup_email(1);
        MockFolderRoot other_path = new MockFolderRoot("other");

        Gee.LinkedList<Email> emails = new Gee.LinkedList<Email>();
        emails.add(e1);

        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath> email_paths =
            new Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath>();
        email_paths.set(e1.id, this.base_folder.path);
        email_paths.set(e1.id, other_path);

        Gee.Collection<Conversation>? added = null;
        Gee.MultiMap<Conversation,Email>? appended = null;
        Gee.Collection<Conversation>? removed = null;
        this.test.add_all_emails(
            emails, email_paths, this.base_folder,
            out added, out appended, out removed
        );

        assert(this.test.size == 1);
        assert(this.test.get_email_count() == 1);

        Conversation convo = this.test.get_by_email_identifier(e1.id);
        assert(convo.is_in_base_folder(e1.id) == true);
        assert(convo.get_folder_count(e1.id) == 2);
    }

    public void add_all_append_path() {
        Email e1 = setup_email(1);
        add_email_to_test_set(e1);

        MockFolderRoot other_path = new MockFolderRoot("other");

        Gee.LinkedList<Email> emails = new Gee.LinkedList<Email>();
        emails.add(e1);

        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath> email_paths =
            new Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath>();
        email_paths.set(e1.id, other_path);

        Gee.Collection<Conversation>? added = null;
        Gee.MultiMap<Conversation,Email>? appended = null;
        Gee.Collection<Conversation>? removed = null;
        this.test.add_all_emails(
            emails, email_paths, this.base_folder,
            out added, out appended, out removed
        );

        assert(this.test.size == 1);
        assert(this.test.get_email_count() == 1);

        assert(added.is_empty);
        assert(appended.size == 0);
        assert(removed.is_empty);

        Conversation convo = this.test.get_by_email_identifier(e1.id);
        assert(convo.is_in_base_folder(e1.id) == true);
        assert(convo.get_folder_count(e1.id) == 2);
    }

    public void remove_all_removed() {
        Email e1 = setup_email(1);
        add_email_to_test_set(e1);

        Conversation convo = this.test.get_by_email_identifier(e1.id);

        Gee.LinkedList<EmailIdentifier> ids =
            new Gee.LinkedList<EmailIdentifier>();
        ids.add(e1.id);

        Gee.Collection<Conversation>? removed = null;
        Gee.MultiMap<Conversation,Email>? trimmed = null;
        this.test.remove_all_emails_by_identifier(
            this.base_folder.path, ids, out removed, out trimmed
        );

        assert(this.test.size == 0);
        assert(this.test.get_email_count() == 0);

        assert(removed != null);
        assert(trimmed != null);

        assert(removed.contains(convo) == true);
        assert(trimmed.size == 0);
    }

    public void remove_all_trimmed() {
        Email e1 = setup_email(1);
        add_email_to_test_set(e1);

        Email e2 = setup_email(2, e1);
        add_email_to_test_set(e2);

        Conversation convo = this.test.get_by_email_identifier(e1.id);

        Gee.LinkedList<EmailIdentifier> ids =
            new Gee.LinkedList<EmailIdentifier>();
        ids.add(e1.id);

        Gee.Collection<Conversation>? removed = null;
        Gee.MultiMap<Conversation,Email>? trimmed = null;
        this.test.remove_all_emails_by_identifier(
            this.base_folder.path, ids, out removed, out trimmed
        );

        assert(this.test.size == 1);
        assert(this.test.get_email_count() == 1);

        assert(removed != null);
        assert(trimmed != null);

        assert(removed.is_empty == true);
        assert(trimmed.contains(convo) == true);
        assert(trimmed.get(convo).contains(e1) == true);
    }

    public void remove_all_remove_path() {
        MockFolderRoot other_path = new MockFolderRoot("other");
        Email e1 = setup_email(1);
        add_email_to_test_set(e1, other_path);

        Conversation convo = this.test.get_by_email_identifier(e1.id);
        assert(convo.get_folder_count(e1.id) == 2);

        Gee.LinkedList<EmailIdentifier> ids =
            new Gee.LinkedList<EmailIdentifier>();
        ids.add(e1.id);

        Gee.Collection<Conversation>? removed = null;
        Gee.MultiMap<Conversation,Email>? trimmed = null;
        this.test.remove_all_emails_by_identifier(
            other_path, ids, out removed, out trimmed
        );

        assert(this.test.size == 1);
        assert(this.test.get_email_count() == 1);

        assert(removed != null);
        assert(removed.is_empty == true);

        assert(trimmed != null);
        assert(trimmed.size == 0);

        assert(convo.is_in_base_folder(e1.id) == true);
        assert(convo.get_folder_count(e1.id) == 1);
    }

    private Email setup_email(int id, Email? references = null) {
        Email email = new Email(new MockEmailIdentifer(id));
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
        email.set_send_date(new Geary.RFC822.Date.from_date_time(now));
        email.set_email_properties(new MockEmailProperties(now));
        email.set_full_references(mid, null, refs_list);
        return email;
    }

    private void add_email_to_test_set(Email to_add,
                                       FolderPath? other_path=null) {
        Gee.LinkedList<Email> emails = new Gee.LinkedList<Email>();
        emails.add(to_add);

        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath> email_paths =
            new Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath>();
        email_paths.set(to_add.id, this.base_folder.path);
        if (other_path != null) {
            email_paths.set(to_add.id, other_path);
        }

        Gee.Collection<Conversation>? added = null;
        Gee.MultiMap<Conversation,Email>? appended = null;
        Gee.Collection<Conversation>? removed = null;
        this.test.add_all_emails(
            emails, email_paths, this.base_folder,
            out added, out appended, out removed
        );
    }

}
