/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.ConfigFileTest : TestCase {


    private const string TEST_KEY = "test-key";
    private const string TEST_KEY_MISSING = "test-key-missing";

    private ConfigFile? test_config = null;
    private ConfigFile.Group? test_group = null;


    public ConfigFileTest() {
        base("Geary.ConfigFileTest");
        add_test("test_string", test_string);
        add_test("test_string_fallback", test_string_fallback);
        add_test("test_string_list", test_string_list);
        add_test("test_string_list", test_string_list);
        add_test("test_bool", test_bool);
        add_test("test_int", test_int);
        add_test("test_uint16", test_uint16);
        add_test("test_has_key", test_has_key);
        add_test("test_key_remove", test_key_remove);
        add_test("test_group_exists", test_group_exists);
        add_test("test_group_remove", test_group_remove);
    }

    public override void set_up() throws GLib.Error {
        this.test_config = new ConfigFile(GLib.File.new_for_path("/tmp/config.ini"));
        this.test_group = this.test_config.get_group("Test");
    }

    public override void tear_down() throws GLib.Error {
        this.test_group = null;
        this.test_config = null;
    }

    public void test_string() throws Error {
        this.test_group.set_string(TEST_KEY, "a string");
        assert_string("a string", this.test_group.get_string(TEST_KEY));
        assert_string("default", this.test_group.get_string(TEST_KEY_MISSING, "default"));
    }

    public void test_string_fallback() throws Error {
        ConfigFile.Group fallback = this.test_config.get_group("fallback");
        fallback.set_string("fallback-test-key", "a string");

        this.test_group.set_fallback("fallback", "fallback-");
        assert_string("a string", this.test_group.get_string(TEST_KEY));
    }

    public void test_string_list() throws Error {
        this.test_group.set_string_list(
            TEST_KEY, new Gee.ArrayList<string>.wrap({ "a", "b"})
        );

        Gee.List<string> saved = this.test_group.get_string_list(TEST_KEY);
        assert_int(2, saved.size, "Saved string list");
        assert_string("a", saved[0]);
        assert_string("b", saved[1]);

        Gee.List<string> def = this.test_group.get_string_list(TEST_KEY_MISSING);
        assert_int(0, def.size, "Default string list");
    }

    public void test_bool() throws Error {
        this.test_group.set_bool(TEST_KEY, true);
        assert_true(this.test_group.get_bool(TEST_KEY));
        assert_true(this.test_group.get_bool(TEST_KEY_MISSING, true));
        assert_false(this.test_group.get_bool(TEST_KEY_MISSING, false));
    }

    public void test_int() throws Error {
        this.test_group.set_int(TEST_KEY, 42);
        assert_int(42, this.test_group.get_int(TEST_KEY));
        assert_int(42, this.test_group.get_int(TEST_KEY_MISSING, 42));
    }

    public void test_uint16() throws Error {
        this.test_group.set_uint16(TEST_KEY, 42);
        assert_int(42, this.test_group.get_uint16(TEST_KEY));
        assert_int(42, this.test_group.get_uint16(TEST_KEY_MISSING, 42));
    }

    public void test_has_key() throws Error {
        assert_false(
            this.test_group.has_key(TEST_KEY),
            "Should not already exist"
        );
        this.test_group.set_string(TEST_KEY, "a string");
        assert_true(
            this.test_group.has_key(TEST_KEY), "Should now exist"
        );
    }

    public void test_key_remove() throws Error {
        // create the key
        this.test_group.set_string(TEST_KEY, "a string");
        assert_true(
            this.test_group.has_key(TEST_KEY), "Should exist"
        );

        this.test_group.remove_key(TEST_KEY);
        assert_false(
            this.test_group.has_key(TEST_KEY), "Should no longer exist"
        );
    }

    public void test_group_exists() throws Error {
        assert_false(this.test_group.exists, "Should not already exist");
        this.test_group.set_string(TEST_KEY, "a string");
        assert_true(this.test_group.exists, "Should now exist");
    }

    public void test_group_remove() throws Error {
        // create the group
        this.test_group.set_string(TEST_KEY, "a string");
        assert_true(this.test_group.exists, "Should exist");

        this.test_group.remove();
        assert_false(this.test_group.exists, "Should no longer exist");
    }

}
