/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class TestAssertions : ValaUnit.TestCase {


    private class TestObject : GLib.Object {  }

    private enum TestEnum { CHECK, ONE, TWO; }

    [Flags]
    private enum TestFlags { CHECK, ONE, TWO; }

    private struct TestStruct {
        public string member;
    }


    public TestAssertions() {
        base("TestAssertions");
        add_test("gobject_equality_assertions", gobject_equality_assertions);
        add_test("string_equality_assertions", string_equality_assertions);
        add_test("int_equality_assertions", int_equality_assertions);
        add_test("short_equality_assertions", short_equality_assertions);
        add_test("long_equality_assertions", long_equality_assertions);
        add_test("uint_equality_assertions", uint_equality_assertions);
        add_test("float_equality_assertions", float_equality_assertions);
        add_test("double_equality_assertions", double_equality_assertions);
        add_test("char_equality_assertions", char_equality_assertions);
        add_test("unichar_equality_assertions", unichar_equality_assertions);
        add_test("enum_equality_assertions", enum_equality_assertions);
        add_test("bool_equality_assertions", bool_equality_assertions);
        add_test("struct_equality_assertions", struct_equality_assertions);
        add_test("string_collection", string_collection);
        add_test("array_collection", array_collection);
        add_test("gee_collection", gee_collection);
    }

    public void gobject_equality_assertions() throws GLib.Error {
        TestObject o1 = new TestObject();
        TestObject o2 = new TestObject();

        expect_equal_success(o1, o1);
        expect_equal_failure(o1, o2);
    }

    public void string_equality_assertions() throws GLib.Error {
        // Consts
        expect_equal_success("foo", "foo");
        expect_equal_failure("foo", "bar");

        // Variables
        var foo1 = "foo";
        var foo2 = "foo";
        var bar = "bar";
        expect_equal_success(foo1, foo1);
        expect_equal_success(foo1, foo2);
        expect_equal_failure(foo1, bar);

        // Boxing variations
        expect_equal_success<string?>(foo1, foo1);
        expect_equal_success<string?>(foo1, foo2);
        expect_equal_failure<string?>(foo1, bar);
        expect_equal_success<string?>("foo", "foo");
        expect_equal_failure<string>("foo", "bar");
        expect_equal_success((string?) foo1, (string?) foo1);
        expect_equal_success((string?) foo1, (string?) foo2);
        expect_equal_failure((string?) foo1, (string?) bar);
        expect_equal_success((string?) "foo", (string?) "foo");
        expect_equal_failure((string?) "foo", (string?) "bar");
    }

    public void int_equality_assertions() throws GLib.Error {
        // Consts
        expect_equal_success<int?>(42, 42);
        expect_equal_failure<int?>(1337, -1);

        // Variables
        int forty_two_a = 42;
        int forty_two_b = 42;
        int l33t = 1337;
        int neg = -1;
        expect_equal_success<int?>(forty_two_a, forty_two_a);
        expect_equal_success<int?>(forty_two_a, forty_two_b);
        expect_equal_failure<int?>(l33t, neg);
    }

    public void short_equality_assertions() throws GLib.Error {
        skip("Cannot determine if a variable is a short. See GNOME/vala#993");

        // Consts
        expect_equal_success<short?>(42, 42);
        expect_equal_failure<short?>(1337, -1);

        // Variables
        short forty_two_a = 42;
        short forty_two_b = 42;
        short l33t = 1337;
        short neg = -1;
        expect_equal_success<short?>(forty_two_a, forty_two_a);
        expect_equal_success<short?>(forty_two_a, forty_two_b);
        expect_equal_failure<short?>(l33t, neg);
    }

    public void long_equality_assertions() throws GLib.Error {
        // Consts
        expect_equal_success<long?>(42, 42);
        expect_equal_failure<long?>(1337, -1);

        // Variables
        long forty_two_a = 42;
        long forty_two_b = 42;
        long l33t = 1337;
        long neg = -1;
        expect_equal_success<long?>(forty_two_a, forty_two_a);
        expect_equal_success<long?>(forty_two_a, forty_two_b);
        expect_equal_failure<long?>(l33t, neg);
    }

    public void int64_equality_assertions() throws GLib.Error {
        // Consts
        expect_equal_success<int64?>(42, 42);
        expect_equal_failure<int64?>(1337, -1);

        // Variables
        int64 forty_two_a = 42;
        int64 forty_two_b = 42;
        int64 l33t = 1337;
        int64 neg = -1;
        expect_equal_success<int64?>(forty_two_a, forty_two_a);
        expect_equal_success<int64?>(forty_two_a, forty_two_b);
        expect_equal_failure<int64?>(l33t, neg);

        // Boundary tests
        var max = int64.MAX;
        var min = int64.MIN;
        expect_equal_success<int64?>(max, max);
        expect_equal_success<int64?>(min, min);
        expect_equal_failure<int64?>(min, max);
        expect_equal_failure<int64?>(max, min);
    }

    public void uint_equality_assertions() throws GLib.Error {
        // Consts
        expect_equal_success<uint?>(42, 42);
        expect_equal_failure<uint?>(1337, -1);

        // Variables
        int forty_two_a = 42;
        int forty_two_b = 42;
        int l33t = 1337;
        int neg = -1;
        expect_equal_success<uint?>(forty_two_a, forty_two_a);
        expect_equal_success<uint?>(forty_two_a, forty_two_b);
        expect_equal_failure<uint?>(l33t, neg);
    }

    public void float_equality_assertions() throws GLib.Error {
        // Consts
        //
        expect_equal_success<float?>(42.0f, 42.0f);
        expect_equal_failure<float?>(1337.0f, (-1.0f));

        // Variables
        float forty_two_a = 42.0f;
        float forty_two_b = 42.0f;
        float l33t = 1337.0f;
        float neg = -1.0f;
        expect_equal_success<float?>(forty_two_a, forty_two_a);
        expect_equal_success<float?>(forty_two_a, forty_two_b);
        expect_equal_failure<float?>(l33t, neg);

        // Boundary tests
        var max = float.MAX;
        var min = float.MIN;
        expect_equal_success<float?>(max, max);
        expect_equal_success<float?>(min, min);
        expect_equal_failure<float?>(min, max);
        expect_equal_failure<float?>(max, min);
    }

    public void double_equality_assertions() throws GLib.Error {
        // Consts
        //
        expect_equal_success<double?>(42.0, 42.0);
        expect_equal_failure<double?>(1337.0, -1.0);

        // Variables
        double forty_two_a = 42.0;
        double forty_two_b = 42.0;
        double l33t = 1337.0;
        double neg = -1.0;
        expect_equal_success<double?>(forty_two_a, forty_two_a);
        expect_equal_success<double?>(forty_two_a, forty_two_b);
        expect_equal_failure<double?>(l33t, neg);

        // Boundary tests
        var max = double.MAX;
        var min = double.MIN;
        expect_equal_success<double?>(max, max);
        expect_equal_success<double?>(min, min);
        expect_equal_failure<double?>(min, max);
        expect_equal_failure<double?>(max, min);
    }

    public void char_equality_assertions() throws GLib.Error {
        expect_equal_success<char?>('a', 'a');
        expect_equal_failure<char?>('a', 'b');
    }

    public void unichar_equality_assertions() throws GLib.Error {
        expect_equal_success<unichar?>('☃', '☃');
        expect_equal_failure<unichar?>('❄', '❅');
    }

    public void enum_equality_assertions() throws GLib.Error {
        expect_equal_success<TestEnum?>(ONE, ONE);
        expect_equal_failure<TestEnum?>(ONE, TWO);
    }

    public void bool_equality_assertions() throws GLib.Error {
        expect_equal_success<bool?>(true, true);
        expect_equal_success<bool?>(false, false);

        expect_equal_failure<bool?>(true, false);
        expect_equal_failure<bool?>(false, true);
    }

    public void struct_equality_assertions() throws GLib.Error {
        var foo = TestStruct() { member = "foo" };

        expect_equal_failure<TestStruct?>(foo, foo);

        // Silence the build warning about `member` being unused
        foo.member += "";
    }

    public void string_collection() throws GLib.Error {
        assert_string("a");
        try {
            assert_string(null);
            fail("Expected null string collection assertion to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }
    }

    public void array_collection() throws GLib.Error {
        assert_array(new string[] { "a" });
        try {
            assert_array<string>(null);
            fail("Expected null array collection assertion to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }
    }

    public void gee_collection() throws GLib.Error {
        assert_collection(new_gee_collection(new string[] { "a" }));
        try {
            assert_collection<Gee.ArrayList<string>>(null);
            fail("Expected null Gee collection assertion to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }
    }

    private void expect_equal_success<T>(T actual,
                                         T expected,
                                         string? context = null)
        throws GLib.Error {
        try {
            assert_equal(actual, expected, context);
        } catch (ValaUnit.TestError.FAILED err) {
            fail(@"Expected equal test to succeed: $(err.message)");
        }
    }

    private void expect_equal_failure<T>(T actual,
                                         T expected,
                                         string? context = null)
        throws GLib.Error {
        try {
            assert_equal(actual, expected, context);
            fail("Expected equal test to fail");
        } catch (ValaUnit.TestError.FAILED err) {
            // all good
        }
    }

    private Gee.Collection<T> new_gee_collection<T>(T[] values) {
        return new Gee.ArrayList<T>.wrap(values);
    }

}
