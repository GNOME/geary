/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class ConversationListModelTest : Gee.TestCase {


    private ConversationListModel? test = null;
    private PreviewLoader? previews = null;
    private Geary.App.ConversationMonitor? monitor = null;
    private Geary.App.EmailStore? store = null;
    private Geary.Folder? base_folder = null;
    private Geary.Account? account = null;
    private Geary.AccountInformation? info = null;


    public ConversationListModelTest() {
        base("ConversationListModel");
        add_test("add_ascending", add_ascending);
        add_test("add_descending", add_descending);
        add_test("add_out_of_order", add_out_of_order);
        add_test("add_duplicate", add_duplicate);
        add_test("remove_first", remove_first);
        add_test("remove_middle", remove_middle);
        add_test("remove_last", remove_last);
        add_test("remove_nonexistent", remove_nonexistent);
    }

    public override void set_up() {
        this.info = new Geary.AccountInformation(
            "test-info",
            File.new_for_path("."),
            File.new_for_path(".")
        );
        this.account = new Geary.MockAccount("test-account", this.info);
        this.base_folder = new Geary.MockFolder(
            this.account,
            null,
            new Geary.MockFolderRoot("test"),
            Geary.SpecialFolderType.NONE,
            null
        );
        this.monitor = new Geary.App.ConversationMonitor(
            this.base_folder,
            Geary.Folder.OpenFlags.NONE,
            Geary.Email.Field.NONE,
            0
        );
        this.store = new Geary.App.EmailStore(this.account);
        this.previews = new PreviewLoader(this.store, new Cancellable());
        this.test = new ConversationListModel(
            this.monitor,
            this.previews
        );
    }

    public void add_ascending() {
        int pos = -1;
        int removed = -1;
        int added = -1;
        this.test.items_changed.connect(
            (item_pos, item_removed, item_added) => {
                pos = (int) item_pos;
                removed = (int) item_removed;
                added = (int) item_added;
            }
        );

        Geary.App.Conversation c1 = setup_conversation(1);
        assert(pos == 0);
        assert(removed == 0);
        assert(added == 1);

        Geary.App.Conversation c2 = setup_conversation(2);
        assert(pos == 0);
        assert(removed == 0);
        assert(added == 1);

        Geary.App.Conversation c3 = setup_conversation(3);
        assert(pos == 0);
        assert(removed == 0);
        assert(added == 1);

        assert(this.test.get_n_items() == 3);
        assert(this.test.get_item(0) == c3);
        assert(this.test.get_item(1) == c2);
        assert(this.test.get_item(2) == c1);
    }

    public void add_descending() {
        int pos = -1;
        int removed = -1;
        int added = -1;
        this.test.items_changed.connect(
            (item_pos, item_removed, item_added) => {
                pos = (int) item_pos;
                removed = (int) item_removed;
                added = (int) item_added;
            }
        );

        Geary.App.Conversation c3 = setup_conversation(3);
        assert(pos == 0);
        assert(removed == 0);
        assert(added == 1);

        Geary.App.Conversation c2 = setup_conversation(2);
        assert(pos == 1);
        assert(removed == 0);
        assert(added == 1);

        Geary.App.Conversation c1 = setup_conversation(1);
        assert(pos == 2);
        assert(removed == 0);
        assert(added == 1);

        assert(this.test.get_n_items() == 3);
        assert(this.test.get_item(0) == c3);
        assert(this.test.get_item(1) == c2);
        assert(this.test.get_item(2) == c1);
    }

    public void add_out_of_order() {
        int pos = -1;
        int removed = -1;
        int added = -1;
        this.test.items_changed.connect(
            (item_pos, item_removed, item_added) => {
                pos = (int) item_pos;
                removed = (int) item_removed;
                added = (int) item_added;
            }
        );

        Geary.App.Conversation c2 = setup_conversation(2);
        assert(pos == 0);
        assert(removed == 0);
        assert(added == 1);

        Geary.App.Conversation c3 = setup_conversation(3);
        assert(pos == 0);
        assert(removed == 0);
        assert(added == 1);

        Geary.App.Conversation c1 = setup_conversation(1);
        assert(pos == 2);
        assert(removed == 0);
        assert(added == 1);

        assert(this.test.get_n_items() == 3);
        assert(this.test.get_item(0) == c3);
        assert(this.test.get_item(1) == c2);
        assert(this.test.get_item(2) == c1);
    }

    public void add_duplicate() {
        Geary.App.Conversation c1 = setup_conversation(1);

        this.test.add(singleton(c1));
        this.test.add(singleton(c1));

        assert(this.test.get_n_items() == 1);
    }

    public void remove_first() {
        int pos = -1;
        int removed = -1;
        int added = -1;
        this.test.items_changed.connect(
            (item_pos, item_removed, item_added) => {
                pos = (int) item_pos;
                removed = (int) item_removed;
                added = (int) item_added;
            }
        );

        Geary.App.Conversation c1 = setup_conversation(1);
        Geary.App.Conversation c2 = setup_conversation(2);
        Geary.App.Conversation c3 = setup_conversation(3);

        this.test.remove(singleton(c1));
        assert(pos == 2);
        assert(removed == 1);
        assert(added == 0);

        assert(this.test.get_n_items() == 2);
        assert(this.test.get_item(0) == c3);
        assert(this.test.get_item(1) == c2);
    }

    public void remove_middle() {
        int pos = -1;
        int removed = -1;
        int added = -1;
        this.test.items_changed.connect(
            (item_pos, item_removed, item_added) => {
                pos = (int) item_pos;
                removed = (int) item_removed;
                added = (int) item_added;
            }
        );

        Geary.App.Conversation c1 = setup_conversation(1, true);
        Geary.App.Conversation c2 = setup_conversation(2);
        Geary.App.Conversation c3 = setup_conversation(3);

        this.test.remove(singleton(c2));
        assert(pos == 1);
        assert(removed == 1);
        assert(added == 0);

        assert(this.test.get_n_items() == 2);
        assert(this.test.get_item(0) == c3);
        assert(this.test.get_item(1) == c1);
    }

    public void remove_last() {
        int pos = -1;
        int removed = -1;
        int added = -1;
        this.test.items_changed.connect(
            (item_pos, item_removed, item_added) => {
                pos = (int) item_pos;
                removed = (int) item_removed;
                added = (int) item_added;
            }
        );

        Geary.App.Conversation c1 = setup_conversation(1);
        Geary.App.Conversation c2 = setup_conversation(2);
        Geary.App.Conversation c3 = setup_conversation(3);

        this.test.remove(singleton(c3));
        assert(pos == 0);
        assert(removed == 1);
        assert(added == 0);

        assert(this.test.get_n_items() == 2);
        assert(this.test.get_item(0) == c2);
        assert(this.test.get_item(1) == c1);
    }

    public void remove_nonexistent() {
        Geary.App.Conversation c1 = setup_conversation(1);
        Geary.App.Conversation c2 = setup_conversation(2);

        this.test.remove(singleton(c2));

        assert(this.test.get_n_items() == 1);
        assert(this.test.get_item(0) == c1);
    }

    private Geary.App.Conversation setup_conversation(int id, bool do_add = true) {
        Geary.App.Conversation conversation = new Geary.App.Conversation(
            this.base_folder
        );
        conversation.add(
            new Geary.Email(new Geary.MockEmailIdentifer(id)),
            singleton(this.base_folder.path)
        );
        if (do_add) {
            this.test.add(singleton(conversation));
        }
        return conversation;
    }

    private Gee.Collection<E> singleton<E>(E element) {
        Gee.LinkedList<E> collection = new Gee.LinkedList<E>();
        collection.add(element);
        return collection;
    }

}
