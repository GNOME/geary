/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.App.ConversationTest : Gee.TestCase {


    Conversation? test = null;
    Folder? base_folder = null;

    public ConversationTest() {
        base("Geary.App.ConversationTest");
        add_test("add_basic", add_basic);
        add_test("add_duplicate", add_duplicate);
        add_test("add_multipath", add_multipath);
        add_test("remove_basic", remove_basic);
        add_test("remove_nonexistent", remove_nonexistent);
    }

    public override void set_up() {
        this.base_folder = new MockFolder(
            null,
            null,
            new MockFolderRoot("test"),
            SpecialFolderType.NONE,
            null
        );
        this.test = new Conversation(this.base_folder);
    }

    public void add_basic() {
        Geary.Email e1 = new Email(new MockEmailIdentifer(1));
        Geary.Email e2 = new Email(new MockEmailIdentifer(2));
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

    public void add_duplicate() {
        Geary.Email e1 = new Email(new MockEmailIdentifer(1));
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

    public void add_multipath() {
        Geary.Email e1 = new Email(new MockEmailIdentifer(1));
        this.test.add(e1, singleton(this.base_folder.path));

        Geary.Email e2 = new Email(new MockEmailIdentifer(2));
        this.test.add(e2, singleton(this.base_folder.path));

        FolderRoot other_path = new MockFolderRoot("other");
        Gee.LinkedList<FolderRoot> other_paths = new Gee.LinkedList<FolderRoot>();
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

    public void remove_basic() {
        Geary.Email e1 = new Email(new MockEmailIdentifer(1));
        this.test.add(e1, singleton(this.base_folder.path));

        Geary.Email e2 = new Email(new MockEmailIdentifer(2));
        this.test.add(e2, singleton(this.base_folder.path));

        uint trimmed = 0;
        this.test.trimmed.connect(() => {
                trimmed++;
            });

        assert(this.test.remove(e1) == null);
        assert(trimmed == 1);
        assert(this.test.get_count() == 1);

        assert(this.test.remove(e2) == null);
        assert(trimmed == 2);
        assert(this.test.get_count() == 0);
    }

    public void remove_nonexistent() {
        Geary.Email e1 = new Email(new MockEmailIdentifer(1));
        Geary.Email e2 = new Email(new MockEmailIdentifer(2));

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

    private Gee.Collection<E> singleton<E>(E element) {
        Gee.LinkedList<E> collection = new Gee.LinkedList<E>();
        collection.add(element);
        return collection;
    }

}
