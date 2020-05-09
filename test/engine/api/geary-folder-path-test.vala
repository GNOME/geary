/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.FolderPathTest : TestCase {


    private const string TEST_LABEL = "#test";

    private FolderRoot? root = null;


    public FolderPathTest() {
        base("Geary.FolderPathTest");
        add_test("get_child_from_root", get_child_from_root);
        add_test("get_child_from_child", get_child_from_child);
        add_test("root_is_root", root_is_root);
        add_test("child_is_not_root", root_is_root);
        add_test("as_array", as_array);
        add_test("is_top_level", is_top_level);
        add_test("distinct_roots_compare", distinct_roots_compare);
        add_test("path_to_string", path_to_string);
        add_test("path_parent", path_parent);
        add_test("path_equal", path_equal);
        add_test("path_hash", path_hash);
        add_test("path_compare", path_compare);
        add_test("path_compare_normalised", path_compare_normalised);
        add_test("root_instances_compare", root_instances_compare);
        add_test("variant_representation", variant_representation);
    }

    public override void set_up() {
        this.root = new FolderRoot(TEST_LABEL, false);
    }

    public override void tear_down() {
        this.root = null;
    }

    public void get_child_from_root() throws GLib.Error {
        assert_equal(this.root.get_child("test").name, "test");
    }

    public void get_child_from_child() throws GLib.Error {
        assert_equal(
            this.root.get_child("test1").get_child("test2").name, "test2"
        );
    }

    public void root_is_root() throws GLib.Error {
        assert_true(this.root.is_root);
    }

    public void child_root_is_not_root() throws GLib.Error {
        assert_false(this.root.get_child("test").is_root);
    }

    public void as_array() throws GLib.Error {
        assert_array(
            this.root.as_array(),
            "Root list"
        ).size(0);

        assert_array(
            this.root.get_child("test").as_array(),
            "Child array"
        ).size(1).contains("test");

        assert_array(
            this.root.get_child("test1").get_child("test2").as_array(),
            "Descendent array"
        ).size(2).first_is("test1").at_index_is(1, "test2");
    }

    public void is_top_level() throws GLib.Error {
        assert_false(this.root.is_top_level, "Root is top_level");
        assert_true(
            this.root.get_child("test").is_top_level,
            "Top level is top_level"
        );
        assert_false(
            this.root.get_child("test").get_child("test").is_top_level,
            "Descendent is top_level"
        );
    }

    public void distinct_roots_compare() throws GLib.Error {
        assert_true(
            this.root.compare_to(new FolderRoot(TEST_LABEL, false)) == 0,
            "Root label equality"
        );
        assert_true(
            this.root.compare_to(new FolderRoot("#other", false)) > 0,
            "Root label inequality"
        );
    }

    public void path_to_string() throws GLib.Error {
        assert_equal(this.root.to_string(), ">");
        assert_equal(this.root.get_child("test").to_string(), ">test");
        assert_equal(
            this.root.get_child("test1").get_child("test2").to_string(),
            ">test1>test2"
        );
    }

    public void path_parent() throws GLib.Error {
        assert_null(this.root.parent, "Root parent");
        assert_string(
            this.root.get_child("test").parent.name,
            "Root child parent"
        ).is_empty();
        assert_equal(
            this.root.get_child("test1").get_child("test2").parent.name,
            "test1",
            "Child parent"
        );
    }

    public void path_equal() throws GLib.Error {
        assert_true(this.root.equal_to(this.root), "Root equality");
        assert_true(
            this.root.get_child("test").equal_to(this.root.get_child("test")),
            "Child equality"
        );
        assert_false(
            this.root.get_child("test1").equal_to(this.root.get_child("test2")),
            "Child names"
        );
        assert_false(
            this.root.get_child("test1").get_child("test")
            .equal_to(this.root.get_child("test2").get_child("test")),
            "Disjoint parents"
        );

        assert_false(
            this.root.get_child("test").equal_to(
                this.root.get_child("").get_child("test")),
            "Pathological case"
        );
    }

    public void path_hash() throws GLib.Error {
        assert_true(
            this.root.hash() !=
            this.root.get_child("test").hash()
        );
        assert_true(
            this.root.get_child("test1").hash() !=
            this.root.get_child("test2").hash()
        );
    }

    public void path_compare() throws GLib.Error {
        // / == /
        assert_compare_eq(this.root.compare_to(this.root), "Root equality");
        // /a == /a
        assert_compare_eq(
            this.root.get_child("a").compare_to(this.root.get_child("a")),
            "Equal child comparison"
        );

        // /a < /b
        assert_compare_lt(
            this.root.get_child("a").compare_to(this.root.get_child("b")),
            "Less than child comparison"
        );

        // /b > /a
        assert_compare_gt(
            this.root.get_child("b").compare_to(this.root.get_child("a")),
            "Greater than child comparison"
        );

        // /a < /a/test
        assert_compare_lt(
            this.root.get_child("a")
            .compare_to(this.root.get_child("a").get_child("test")),
            "Less than descendant"
        );

        // /a/test > /a
        assert_compare_gt(
            this.root.get_child("a").get_child("test")
            .compare_to(this.root.get_child("a")),
            "Greater than descendant"
        );

        // /a/b == /a/b
        assert_compare_eq(
            this.root.get_child("a").get_child("b")
            .compare_to(this.root.get_child("a").get_child("b")),
            "N-path equality"
        );

        // /a/test < /b/test
        assert_compare_lt(
            this.root.get_child("a").get_child("test")
            .compare_to(this.root.get_child("b").get_child("test")),
            "Less than disjoint paths"
        );

        // /b/test > /a/test
        assert_compare_gt(
            this.root.get_child("b").get_child("test")
            .compare_to(this.root.get_child("a").get_child("test")),
            "Greater than disjoint paths"
        );

        // /a/d < /b/c
        assert_compare_lt(
            this.root.get_child("a").get_child("d")
            .compare_to(this.root.get_child("b").get_child("c")),
            "Less than double disjoint"
        );

        // /b/c > /a/d
        assert_compare_gt(
            this.root.get_child("b").get_child("c")
            .compare_to(this.root.get_child("a").get_child("d")),
            "Less than double disjoint"
        );

    }

    public void path_compare_normalised() throws GLib.Error {
        assert_compare_eq(
            this.root.compare_normalized_ci(this.root), "Root equality"
        );
        assert_compare_eq(
            this.root.get_child("a").compare_normalized_ci(this.root.get_child("a")),
            "Equal child comparison"
        );

        assert_compare_lt(
            this.root.get_child("a").compare_normalized_ci(this.root.get_child("b")),
            "Greater than child comparison"
        );

        assert_compare_gt(
            this.root.get_child("b").compare_normalized_ci(this.root.get_child("a")),
            "Less than child comparison"
        );

        assert_compare_lt(
            this.root.get_child("a").get_child("test")
            .compare_normalized_ci(this.root.get_child("b").get_child("test")),
            "Greater than disjoint parents"
        );
        assert_compare_gt(
            this.root.get_child("b").get_child("test")
            .compare_normalized_ci(this.root.get_child("a").get_child("test")),
            "Less than disjoint parents"
        );

        assert_compare_gt(
            this.root.get_child("a").get_child("test")
            .compare_normalized_ci(this.root.get_child("a")),
            "Greater than descendant"
        );
        assert_compare_lt(
            this.root.get_child("a")
            .compare_normalized_ci(this.root.get_child("a").get_child("test")),
            "Less than descendant"
        );
    }

    public void root_instances_compare() throws GLib.Error {
        assert_compare_eq(
            this.root.compare_to(new FolderRoot(TEST_LABEL, false)),
            "Root equality"
        );
        assert_compare_eq(
            this.root.get_child("a").compare_to(new FolderRoot(TEST_LABEL, false).get_child("a")),
            "Equal child comparison"
        );

        assert_compare_gt(
            this.root.get_child("a").compare_to(
                new FolderRoot("#other", false).get_child("a")),
            "Root label inequality with children"
        );

        assert_compare_lt(
            this.root.get_child("a").compare_to(new FolderRoot(TEST_LABEL, false).get_child("b")),
            "Greater than child comparison"
        );

        assert_compare_gt(
            this.root.get_child("b").compare_to(new FolderRoot(TEST_LABEL, false).get_child("a")),
            "Less than child comparison"
        );

        assert_compare_gt(
            this.root.get_child("a").get_child("test")
            .compare_to(new FolderRoot(TEST_LABEL, false).get_child("a")),
            "Greater than descendant"
        );
        assert_true(
            this.root.get_child("a")
            .compare_to(new FolderRoot(TEST_LABEL, false).get_child("a").get_child("test")) < 0,
            "Less than descendant"
        );

        assert_compare_eq(
            this.root.get_child("a").get_child("b")
            .compare_to(new FolderRoot(TEST_LABEL, false).get_child("a").get_child("b")),
            "N-path equality"
        );

        assert_compare_lt(
            this.root.get_child("a").get_child("a")
            .compare_to(new FolderRoot(TEST_LABEL, false).get_child("b").get_child("b")),
            "Less than double disjoint"
        );
        assert_compare_gt(
            this.root.get_child("b").get_child("a")
            .compare_to(new FolderRoot(TEST_LABEL, false).get_child("a").get_child("a")),
            "Greater than double disjoint"
        );

    }

    public void variant_representation() throws GLib.Error {
        FolderPath orig = this.root.get_child("test");
        GLib.Variant variant = orig.to_variant();
        FolderPath copy = this.root.from_variant(variant);

        assert_true(orig.equal_to(copy));
    }

}
