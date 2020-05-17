/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class CollectionAssertions : ValaUnit.TestCase {



    public CollectionAssertions() {
        base("CollectionAssertions");
        add_test("string_collection", string_collection);
        add_test("string_array_collection", string_array_collection);
        add_test("int_array_collection", int_array_collection);
        add_test("string_gee_collection", string_gee_collection);
        add_test("int_gee_collection", int_gee_collection);
    }

    public void string_collection() throws GLib.Error {
        assert_string("hello", "non-empty string")
            .is_non_empty()
            .size(5)
            .contains("lo")
            .not_contains("☃")
            .first_is("h")
            .first_is("hell")
            .at_index_is(1, "e")
            .at_index_is(1, "ell");


        assert_string("", "empty string")
            .is_empty()
            .size(0)
            .contains("")
            .not_contains("☃");

        try {
            assert_string("").is_non_empty();
            fail("Expected ::is_non_empty to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }

        try {
            assert_string("hello").is_empty();
            fail("Expected ::is_empty to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }

        try {
            assert_string("hello").contains("☃");
            fail("Expected ::contains to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }
    }

    public void string_array_collection() throws GLib.Error {
        assert_array(new string[] { "hello", "world"})
            .is_non_empty()
            .size(2)
            .contains("hello")
            .not_contains("☃")
            .first_is("hello")
            .at_index_is(1, "world");


        assert_array(new string[0])
            .is_empty()
            .size(0)
            .not_contains("☃");

        try {
            assert_array(new string[0]).is_non_empty();
            fail("Expected ::is_non_empty to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }

        try {
            assert_array(new string[] { "hello", "world"}).is_empty();
            fail("Expected ::is_empty to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }

        try {
            assert_array(new string[] { "hello", "world"}).contains("☃");
            fail("Expected ::contains to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }
    }

    public void int_array_collection() throws GLib.Error {
        skip("Arrays containing non-pointer values not currently supported. See GNOME/vala#964");
        int[] array = new int[] { 42, 1337 };
        int[] empty = new int[0];

        assert_array(array)
            .is_non_empty()
            .size(2)
            .contains(42)
            .not_contains(-1)
            .first_is(42)
            .at_index_is(1, 1337);

        assert_array(empty)
            .is_empty()
            .size(0)
            .not_contains(42);

        try {
            assert_array(empty).is_non_empty();
            fail("Expected ::is_non_empty to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }

        try {
            assert_array(array).is_empty();
            fail("Expected ::is_empty to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }

        try {
            assert_array(array).contains(-1);
            fail("Expected ::contains to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }
    }

    public void string_gee_collection() throws GLib.Error {
        var strv = new string[] { "hello", "world" };
        assert_collection(new_gee_collection(strv))
            .is_non_empty()
            .size(2)
            .contains("hello")
            .not_contains("☃")
            .first_is("hello")
            .at_index_is(1, "world");

        assert_collection(new_gee_collection(new string[0]))
            .is_empty()
            .size(0)
            .not_contains("☃");

        try {
            assert_collection(new_gee_collection(new string[0])).is_non_empty();
            fail("Expected ::is_non_empty to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }

        try {
            assert_collection(new_gee_collection(strv)).is_empty();
            fail("Expected ::is_empty to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }

        try {
            assert_collection(new_gee_collection(strv)).contains("☃");
            fail("Expected ::contains to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }
    }

    public void int_gee_collection() throws GLib.Error {
#if !VALA_0_50
        skip("Collections containing non-pointer values not currently supported. See GNOME/vala#992");
#endif
        var intv = new int[] { 42, 1337 };
        assert_collection(new_gee_collection(intv))
            .is_non_empty()
            .size(2)
            .contains(42)
            .not_contains(-1)
            .first_is(42)
            .at_index_is(1, 1337);

        assert_collection(new_gee_collection(new int[0]))
            .is_empty()
            .size(0)
            .not_contains(42);

        try {
            assert_collection(new_gee_collection(new int[0])).is_non_empty();
            fail("Expected ::is_non_empty to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }

        try {
            assert_collection(new_gee_collection(intv)).is_empty();
            fail("Expected ::is_empty to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }

        try {
            assert_collection(new_gee_collection(intv)).contains(-1);
            fail("Expected ::contains to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }
    }

    private Gee.Collection<T> new_gee_collection<T>(T[] values) {
        return new Gee.ArrayList<T>.wrap(values);
    }

}
