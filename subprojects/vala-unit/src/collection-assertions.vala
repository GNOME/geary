/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Defines default test assertions for specific strings, arrays and collections.
 *
 * Call {@link TestAssertions.assert_string}, {@link
 * TestAssertions.assert_array} and {@link
 * TestAssertions.assert_collection} methods, accessible from
 * subclasses of {@link TestCase} to construct these objects.
 */
public interface ValaUnit.CollectionAssertions<E> : GLib.Object {


    /**
     * Asserts the collection is empty.
     *
     * Returns the same object to allow assertion chaining.
     */
    public abstract CollectionAssertions<E> is_empty()
        throws GLib.Error;

    /**
     * Asserts the collection is non-empty.
     *
     * Returns the same object to allow assertion chaining.
     */
    public abstract CollectionAssertions<E> is_non_empty()
        throws GLib.Error;

    /**
     * Asserts the collection has an expected length.
     *
     * Returns the same object to allow assertion chaining.
     */
    public abstract CollectionAssertions<E> size(uint32 expected)
        throws GLib.Error;

    /**
     * Asserts the collection contains an expected element.
     *
     * Returns the same object to allow assertion chaining.
     */
    public abstract CollectionAssertions<E> contains(E expected)
        throws GLib.Error;

    /**
     * Asserts the collection does not contain an expected element.
     *
     * Returns the same object to allow assertion chaining.
     */
    public abstract CollectionAssertions<E> not_contains(E expected)
        throws GLib.Error;

    /**
     * Asserts the collection's first element is as expected.
     *
     * Returns the same object to allow assertion chaining.
     */
    public CollectionAssertions<E> first_is(E expected)
        throws GLib.Error {
        at_index_is(0, expected);
        return this;
    }

    /**
     * Asserts the collection's nth element is as expected.
     *
     * Note the give position is is 1-based, not 0-based.
     *
     * Returns the same object to allow assertion chaining.
     */
    public abstract CollectionAssertions<E> at_index_is(uint32 position,
                                                        E expected)
        throws GLib.Error;


}

internal class ValaUnit.StringCollectionAssertion : GLib.Object,
    CollectionAssertions<string> {


    private string actual;
    private string? context;


    internal StringCollectionAssertion(string actual, string? context) {
        this.actual = actual;
        this.context = context;
    }

    public CollectionAssertions<string> is_empty() throws GLib.Error {
        if (this.actual.length != 0) {
            ValaUnit.assert(
                "“%s”.length = %u, expected empty".printf(
                    this.actual,
                    this.actual.length
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<string> is_non_empty()
        throws GLib.Error {
        if (this.actual.length == 0) {
            ValaUnit.assert(
                "string is empty, expected non-empty", this.context
            );
        }
        return this;
    }

    public CollectionAssertions<string> size(uint32 expected)
        throws GLib.Error {
        if (this.actual.length != expected) {
            ValaUnit.assert(
                "“%s”.length = %u, expected %u".printf(
                    this.actual,
                    this.actual.length,
                    expected
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<string> contains(string expected)
        throws GLib.Error {
        if (!(expected in this.actual)) {
            ValaUnit.assert(
                "“%s” does not contain “%s”".printf(
                    this.actual,
                    expected
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<string> not_contains(string expected)
        throws GLib.Error {
        if (expected in this.actual) {
            ValaUnit.assert(
                "“%s” should not contain “%s”".printf(
                    this.actual,
                    expected
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<string> at_index_is(uint32 index,
                                                    string expected)
        throws GLib.Error {
        if (this.actual.index_of(expected) != index) {
            ValaUnit.assert(
                "“%s”[%u:%u] != “%s”".printf(
                    this.actual,
                    index,
                    index + (uint) expected.length,
                    expected
                ),
                this.context
            );
        }
        return this;
    }

}


internal class ValaUnit.ArrayCollectionAssertion<E> : GLib.Object,
    CollectionAssertions<E> {


    private E[] actual;
    private string? context;


    internal ArrayCollectionAssertion(E[] actual, string? context)
        throws TestError {
        this.actual = actual;
        this.context = context;

        GLib.Type UNSUPPORTED[] = {
            typeof(bool),
            typeof(char),
            typeof(short),
            typeof(int),
            typeof(int64),
            typeof(uchar),
            typeof(ushort),
            typeof(uint),
            typeof(uint64),
            typeof(float),
            typeof(double)
        };
        var type = typeof(E);
        if (type.is_enum() || type in UNSUPPORTED) {
            throw new TestError.UNSUPPORTED(
                "Arrays containing non-pointer values not currently supported. See GNOME/vala#964"
            );
        }
    }

    public CollectionAssertions<E> is_empty() throws GLib.Error {
        if (this.actual.length != 0) {
            ValaUnit.assert(
                "%s is not empty".printf(
                    to_collection_display()
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<E> is_non_empty()
        throws GLib.Error {
        if (this.actual.length == 0) {
            ValaUnit.assert(
                "%s is empty, expected non-empty".printf(
                    to_collection_display()
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<E> size(uint32 expected)
        throws GLib.Error {
        if (this.actual.length != expected) {
            ValaUnit.assert(
                "%s.length == %d, expected %u".printf(
                    to_collection_display(),
                    this.actual.length,
                    expected
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<E> contains(E expected)
        throws GLib.Error {
        E? boxed_expected = box_value(expected);
        bool found = false;
        for (int i = 0; i < this.actual.length; i++) {
            try {
                assert_equal(box_value(this.actual[i]), boxed_expected);
                found = true;
                break;
            } catch (TestError.FAILED err) {
                // no-op
            }
        }
        if (!found) {
            ValaUnit.assert(
                "%s does not contain %s".printf(
                    to_collection_display(),
                    to_display_string(boxed_expected)
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<E> not_contains(E expected)
        throws GLib.Error {
        E? boxed_expected = box_value(expected);
        for (int i = 0; i < this.actual.length; i++) {
            try {
                assert_equal(box_value(this.actual[i]), boxed_expected);
                ValaUnit.assert(
                    "%s does not contain %s".printf(
                        to_collection_display(),
                        to_display_string(boxed_expected)
                    ),
                    this.context
                );
                break;
            } catch (TestError.FAILED err) {
                // no-op
            }
        }
        return this;
    }

    public CollectionAssertions<E> at_index_is(uint32 index, E expected)
        throws GLib.Error {
        if (index >= this.actual.length) {
            ValaUnit.assert(
                "%s.length == %u, expected >= %u".printf(
                    to_collection_display(),
                    this.actual.length,
                    index
                ),
                this.context
            );
        }
        E? boxed_actual = box_value(this.actual[index]);
        E? boxed_expected = box_value(expected);
        try {
            assert_equal(boxed_actual, boxed_expected);
        } catch (TestError.FAILED err) {
            ValaUnit.assert(
                "%s[%u] == %s, expected: %s".printf(
                    to_collection_display(),
                    index,
                    to_display_string(boxed_actual),
                    to_display_string(boxed_expected)
                ),
                this.context
            );
        }
        return this;
    }

    private string to_collection_display() {
        var buf = new GLib.StringBuilder();
        int len = this.actual.length;
        buf.append(typeof(E).name());
        buf.append("[]");

        if (len > 0) {
            buf.append_c('{');
            buf.append(to_display_string(box_value(this.actual[0])));

            if (len == 2) {
                buf.append_c(',');
                buf.append(to_display_string(box_value(this.actual[1])));
            } else if (len > 2) {
                buf.append(", … (%d more)".printf(len - 2));
            }
            buf.append_c('}');
        }
        return buf.str;
    }

}


internal class ValaUnit.GeeCollectionAssertion<E> :
    GLib.Object,
    CollectionAssertions<E> {


    private Gee.Collection<E> actual;
    private string? context;


    internal GeeCollectionAssertion(Gee.Collection<E> actual, string? context) {
        this.actual = actual;
        this.context = context;
    }

    public CollectionAssertions<E> is_empty() throws GLib.Error {
        if (!this.actual.is_empty) {
            ValaUnit.assert(
                "%s.length = %d, expected empty".printf(
                    to_collection_display(),
                    this.actual.size
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<E> is_non_empty()
        throws GLib.Error {
        if (this.actual.is_empty) {
            ValaUnit.assert(
                "%s is empty, expected non-empty".printf(
                    to_collection_display()
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<E> size(uint32 expected)
        throws GLib.Error {
        if (this.actual.size != expected) {
            ValaUnit.assert(
                "%s.size == %d, expected %u".printf(
                    to_collection_display(),
                    this.actual.size,
                    expected
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<E> contains(E expected)
        throws GLib.Error {
        if (!(expected in this.actual)) {
            ValaUnit.assert(
                "%s does not contain %s".printf(
                    to_collection_display(),
                    to_display_string(box_value(expected))
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<E> not_contains(E expected)
        throws GLib.Error {
        if (expected in this.actual) {
            ValaUnit.assert(
                "%s should not contain %s".printf(
                    to_collection_display(),
                    to_display_string(box_value(expected))
                ),
                this.context
            );
        }
        return this;
    }

    public CollectionAssertions<E> at_index_is(uint32 index, E expected)
        throws GLib.Error {
        if (index >= this.actual.size) {
            ValaUnit.assert(
                "%s.length == %d, expected >= %u".printf(
                    to_collection_display(),
                    this.actual.size,
                    index
                ),
                this.context
            );
        }
        Gee.Iterator<E> iterator = this.actual.iterator();
        for (int i = 0; i <= index; i++) {
            iterator.next();
        }
        E? boxed_actual = box_value(iterator.get());
        E? boxed_expected = box_value(expected);
        try {
            assert_equal(boxed_actual, boxed_expected);
        } catch (TestError.FAILED err) {
            ValaUnit.assert(
                "%s[%u] == %s, expected: %s".printf(
                    to_collection_display(),
                    index,
                    to_display_string(boxed_actual),
                    to_display_string(boxed_expected)
                ),
                this.context
            );
        }
        return this;
    }

    private string to_collection_display() {
        var buf = new GLib.StringBuilder();
        int len = this.actual.size;
        buf.append("Gee.Collection<");
        buf.append(typeof(E).name());
        buf.append_c('>');

        if (len > 0) {
            Gee.Iterator<E> iterator = this.actual.iterator();
            iterator.next();
            buf.append_c('{');
            buf.append(to_display_string(box_value(iterator.get())));

            if (len == 2) {
                iterator.next();
                buf.append_c(',');
                buf.append(to_display_string(box_value(iterator.get())));
            } else if (len > 2) {
                buf.append(", … (%d more)".printf(len - 2));
            }
            buf.append_c('}');
        }
        return buf.str;
    }

}
