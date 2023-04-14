/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

namespace ValaUnit {

    /** Error thrown when a test condition has failed */
    public errordomain TestError {

        /** Thrown when test assertion failed. */
        FAILED,

        /** Thrown when test has been skipped. */
        SKIPPED,

        /** Thrown when an assertion is not currently supported. */
        UNSUPPORTED;

    }

    internal inline void assert_equal<T>(T? actual,
                                         T? expected,
                                         string? context = null)
        throws TestError {
        if ((actual == null && expected != null) ||
            (actual != null && expected == null)) {
            assert_is_not_equal(actual, expected, context);
        }
        if (actual != null && expected != null) {
            // Can't just do a direct comparison here, since under the
            // hood we'll be comparing gconstpointers, which will
            // nearly always be incorrect
            var type = typeof(T);
            if (type.is_object()) {
                if (((GLib.Object) actual) !=
                    ((GLib.Object) expected)) {
                    ValaUnit.assert(
                        "%s are not equal".printf(typeof(T).name()),
                        context
                    );
                }
            } else if (type.is_enum()) {
                assert_equal_enum<T>(actual, expected, context);
            } else if (type == typeof(string)) {
                assert_equal_string((string?) actual, (string?) expected, context);
            } else if (type == typeof(int)) {
                assert_equal_int((int?) actual, (int?) expected, context);
            } else if (type == typeof(short)) {
                assert_equal_short((short?) actual, (short?) expected, context);
            } else if (type == typeof(char)) {
                assert_equal_char((char?) actual, (char?) expected, context);
            } else if (type == typeof(long)) {
                assert_equal_long((long?) actual, (long?) expected, context);
            } else if (type == typeof(int64)) {
                assert_equal_int64((int64?) actual, (int64?) expected, context);
            } else if (type == typeof(uint)) {
                assert_equal_uint((uint?) actual, (uint?) expected, context);
            } else if (type == typeof(uchar)) {
                assert_equal_uchar((uchar?) actual, (uchar?) expected, context);
            } else if (type == typeof(ushort)) {
                assert_equal_ushort((ushort?) actual, (ushort?) expected, context);
            } else if (type == typeof(ulong)) {
                assert_equal_ulong((ulong?) actual, (ulong?) expected, context);
            } else if (type == typeof(uint64)) {
                assert_equal_uint64((uint64?) actual, (uint64?) expected, context);
            } else if (type == typeof(double)) {
                assert_equal_double((double?) actual, (double?) expected, context);
            } else if (type == typeof(float)) {
                assert_equal_float((float?) actual, (float?) expected, context);
            } else if (type == typeof(bool)) {
                assert_equal_bool((bool?) actual, (bool?) expected, context);
            } else {
                ValaUnit.assert(
                    "%s is not a supported type for equality tests".printf(
                        type.name()
                    ),
                    context
                );
            }
        }
    }

    internal inline void assert(string message, string? context)
        throws TestError {
        var buf = new GLib.StringBuilder();
        if (context != null) {
            buf.append_c('[');
            buf.append((string) context);
            buf.append("] ");
        }
        buf.append(message);

        throw new TestError.FAILED(buf.str);
    }

    /**
     * Unpacks generics-based value types and repacks as boxed.
     *
     * Per GNOME/vala#564, non-boxed, non-pointer values will be
     * passed as a pointer, where the memory address of the pointer is
     * the actual value (!). This method works around that by casting
     * back to a value, then boxing so that the value is allocated and
     * passed by reference instead.
     *
     * This will only work when the values are not already boxed.
     */
    internal T? box_value<T>(T value) {
        var type = typeof(T);
        T? boxed = value;

        if (type == typeof(int) || type.is_enum()) {
            int actual = (int) value;
            boxed = (int?) actual;
        } else if (type == typeof(short)) {
            short actual = (short) value;
            boxed = (short?) actual;
        } else if (type == typeof(char)) {
        } else if (type == typeof(long)) {
        } else if (type == typeof(int64)) {
        } else if (type == typeof(uint)) {
        } else if (type == typeof(uchar)) {
        } else if (type == typeof(ushort)) {
        } else if (type == typeof(ulong)) {
        } else if (type == typeof(uint64)) {
        } else if (type == typeof(double)) {
        } else if (type == typeof(float)) {
        } else if (type == typeof(bool)) {
        }

        return boxed;
    }

    internal string to_display_string<T>(T? value) {
        var type = typeof(T);
        var display = "";

        if (value == null) {
            display = "(null)";
        } else if (type == typeof(string)) {
            display = "“%s”".printf((string) ((string?) value));
        } else if (type.is_enum()) {
            display = GLib.EnumClass.to_string(
                typeof(T), (int) ((int?) value)
            );
        } else if (type == typeof(int)) {
            display = ((int) ((int?) value)).to_string();
        } else if (type == typeof(short)) {
            display = ((short) ((short?) value)).to_string();
        } else if (type == typeof(char)) {
            display = "‘%s’".printf(((char) ((char?) value)).to_string());
        } else if (type == typeof(long)) {
            display = ((long) ((long?) value)).to_string();
        } else if (type == typeof(int64)) {
            display = ((int64) ((int64?) value)).to_string();
        } else if (type == typeof(uint)) {
            display = ((uint) ((uint?) value)).to_string();
        } else if (type == typeof(uchar)) {
            display = "‘%s’".printf(((uchar) ((uchar?) value)).to_string());
        } else if (type == typeof(ushort)) {
            display = ((ushort) ((ushort?) value)).to_string();
        } else if (type == typeof(ulong)) {
            display = ((long) ((long?) value)).to_string();
        } else if (type == typeof(uint64)) {
            display = ((uint64) ((uint64?) value)).to_string();
        } else if (type == typeof(double)) {
            display = ((double) ((double?) value)).to_string();
        } else if (type == typeof(float)) {
            display = ((float) ((float?) value)).to_string();
        } else if (type == typeof(bool)) {
            display = ((bool) ((bool?) value)).to_string();
        } else {
            display = type.name();
        }

        return display;
    }

    private inline void assert_is_not_equal<T>(T actual,
                                               T expected,
                                               string? context)
        throws TestError {
        assert(
            "%s != %s".printf(
                to_display_string(actual),
                to_display_string(expected)
            ),
            context
        );
    }

    private void assert_equal_enum<T>(T? actual,
                                      T? expected,
                                      string? context)
        throws TestError {
        int actual_val = (int) ((int?) actual);
        int expected_val = (int) ((int?) expected);
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_string(string? actual,
                                     string? expected,
                                     string? context)
        throws TestError {
        string actual_val = (string) actual;
        string expected_val = (string) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_int(int? actual, int? expected, string? context)
        throws TestError {
        int actual_val = (int) actual;
        int expected_val = (int) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_char(char? actual, char? expected, string? context)
        throws TestError {
        char actual_val = (char) actual;
        char expected_val = (char) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_short(short? actual, short? expected, string? context)
        throws TestError {
        short actual_val = (short) actual;
        short expected_val = (short) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_long(long? actual, long? expected, string? context)
        throws TestError {
        long actual_val = (long) actual;
        long expected_val = (long) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_int64(int64? actual, int64? expected, string? context)
        throws TestError {
        int64 actual_val = (int64) actual;
        int64 expected_val = (int64) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_uint(uint? actual, uint? expected, string? context)
        throws TestError {
        uint actual_val = (uint) actual;
        uint expected_val = (uint) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_uchar(uchar? actual, uchar? expected, string? context)
        throws TestError {
        uchar actual_val = (uchar) actual;
        uchar expected_val = (uchar) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_ushort(ushort? actual, ushort? expected, string? context)
        throws TestError {
        ushort actual_val = (ushort) actual;
        ushort expected_val = (ushort) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_ulong(ulong? actual, ulong? expected, string? context)
        throws TestError {
        ulong actual_val = (ulong) actual;
        ulong expected_val = (ulong) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_uint64(uint64? actual, uint64? expected, string? context)
        throws TestError {
        uint64 actual_val = (uint64) actual;
        uint64 expected_val = (uint64) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_float(float? actual, float? expected, string? context)
        throws TestError {
        float actual_val = (float) actual;
        float expected_val = (float) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_double(double? actual, double? expected, string? context)
        throws TestError {
        double actual_val = (double) actual;
        double expected_val = (double) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

    private void assert_equal_bool(bool? actual, bool? expected, string? context)
        throws TestError {
        bool actual_val = (bool) actual;
        bool expected_val = (bool) expected;
        if (actual_val != expected_val) {
            assert_is_not_equal(actual, expected, context);
        }
    }

}

/**
 * Defines default test assertions.
 *
 * Note that {@link TestCase} implements this, so when making
 * assertions in test methods, you can just call these directly.
 */
public interface ValaUnit.TestAssertions : GLib.Object {


    /** Asserts a value is null */
    public void assert_non_null<T>(T? actual, string? context = null)
        throws TestError {
        if (actual == null) {
            ValaUnit.assert(
                "%s is null, expected non-null".printf(typeof(T).name()),
                context
            );
        }
    }

    /** Asserts a value is null */
    public void assert_is_null<T>(T? actual, string? context = null)
        throws TestError {
        if (actual != null) {
            ValaUnit.assert(
                "%s is non-null, expected null".printf(typeof(T).name()),
                context
            );
        }
    }

    /** Asserts the two given values refer to the same object or value. */
    public void assert_equal<T>(T actual, T expected, string? context = null)
        throws TestError {
        ValaUnit.assert_equal(actual, expected, context);
    }

    /** Asserts the two given values refer to the same object or value. */
    public void assert_within(double actual,
                              double expected,
                              double epsilon,
                              string? context = null)
        throws TestError {
        if (actual > expected + epsilon || actual < expected - epsilon) {
            ValaUnit.assert(
                "%f is not within ±%f of %f".printf(actual, epsilon, expected),
                context
            );
        }
    }

    /** Asserts a Boolean value is true. */
    public void assert_true(bool actual, string? context = null)
        throws TestError {
        if (!actual) {
            ValaUnit.assert("Is false, expected true", context);
        }
    }

    /** Asserts a Boolean value is false. */
    public void assert_false(bool actual, string? context = null)
        throws TestError {
        if (actual) {
            ValaUnit.assert("Is true, expected false", context);
        }
    }

    /** Asserts a collection is non-null and empty. */
    public CollectionAssertions<string> assert_string(string? actual,
                                                      string? context = null)
        throws TestError {
        if (actual == null) {
            ValaUnit.assert("Expected a string, was null", context);
        }
        return new StringCollectionAssertion((string) actual, context);
    }

    /** Asserts a collection is non-null and empty. */
    public CollectionAssertions<E> assert_array<E>(E[]? actual,
                                                   string? context = null)
        throws TestError {
        if (actual == null) {
            ValaUnit.assert("Expected an array, was null", context);
        }
        return new ArrayCollectionAssertion<E>((E[]) actual, context);
    }

    /** Asserts an array is null */
    public void assert_array_is_null<T>(T[]? actual, string? context = null)
        throws TestError {
        if (actual != null) {
            ValaUnit.assert(
                "%s is non-null, expected null".printf(typeof(T).name()),
                context
            );
        }
    }

    /** Asserts a collection is non-null and empty. */
    public CollectionAssertions<E> assert_collection<E>(
        Gee.Collection<E>? actual,
        string? context = null
    ) throws TestError {
        if (actual == null) {
            ValaUnit.assert("Expected a collection, was null", context);
        }
        return new GeeCollectionAssertion<E>(
            (Gee.Collection<E>) actual, context
        );
    }

    /** Asserts a comparator value is equal, that is, 0. */
    public void assert_compare_eq(int actual, string? context = null)
        throws TestError {
        if (actual != 0) {
            ValaUnit.assert(
                "Comparison is not equal: %d".printf(actual), context
            );
        }
    }

    /** Asserts a comparator value is greater-than, that is, > 0. */
    public void assert_compare_gt(int actual, string? context = null)
        throws TestError {
        if (actual < 0) {
            ValaUnit.assert(
                "Comparison is not greater than: %d".printf(actual), context
            );
        }
    }

    /** Asserts a comparator value is less-than, that is, < 0. */
    public void assert_compare_lt(int actual, string? context = null)
        throws TestError {
        if (actual > 0) {
            ValaUnit.assert(
                "Comparison is not less than: %d".printf(actual), context
            );
        }
    }

    /**
     * Asserts an error matches an expected type.
     *
     * The actual error's domain and code must be the same as that of
     * the expected, but its message is ignored.
     */
    public void assert_error(GLib.Error? actual,
                             GLib.Error expected,
                             string? context = null) throws TestError {
        if (actual == null) {
            ValaUnit.assert(
                "Expected error: %s %i, was null".printf(
                    expected.domain.to_string(), expected.code
                ),
                context
            );
        } else {
            var non_null = (GLib.Error) actual;
            if (expected.domain != non_null.domain ||
                expected.code != non_null.code) {
                ValaUnit.assert(
                    "Expected error: %s %i, was actually %s %i: %s".printf(
                        expected.domain.to_string(),
                        expected.code,
                        non_null.domain.to_string(),
                        non_null.code,
                    non_null.message
                    ),
                    context
                );
            }
        }
    }

    public void assert_no_error(GLib.Error? err, string? context = null)
        throws TestError {
        if (err != null) {
            var non_null = (GLib.Error) err;
            ValaUnit.assert(
                "Unexpected error: %s %i: %s".printf(
                    non_null.domain.to_string(),
                    non_null.code,
                    non_null.message
                ),
                context
            );
        }
    }

    // The following deliberately shadow un-prefixed GLib calls so as
    // to get consistent behaviour when called

    /**
     * Asserts a Boolean value is true.
     */
    public void assert(bool actual, string? context = null)
        throws TestError {
        assert_true(actual, context);
    }

    /** Asserts a value is null. */
    public void assert_null<T>(T actual, string? context = null)
        throws TestError {
        assert_is_null(actual, context);
    }

    /**
     * Asserts this call is never made.
     */
    public void assert_not_reached(string? context = null)
        throws TestError {
        ValaUnit.assert("This call should not be reached", context);
    }

}
