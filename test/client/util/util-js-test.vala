/*
 * Copyright © 2017-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Util.JS.Test : TestCase {


    private JSC.Context? context = null;


    public Test() {
        base("Util.JS.Test");
        add_test("to_variant", to_variant);
        add_test("to_value", to_value);
    }

    public override void set_up() throws GLib.Error {
        this.context = new JSC.Context();
    }

    public override void tear_down() throws GLib.Error {
        this.context = null;
    }

    public void to_variant() throws GLib.Error {
        assert_equal(
            value_to_variant(new JSC.Value.null(this.context)).print(true),
            "@mv nothing"
        );
        assert_equal(
            value_to_variant(new JSC.Value.string(this.context, "test")).print(true),
            "'test'"
        );
        assert_equal(
            value_to_variant(new JSC.Value.number(this.context, 1.0)).print(true),
            "1.0"
        );
        assert_equal(
            value_to_variant(new JSC.Value.boolean(this.context, true)).print(true),
            "true"
        );
        assert_equal(
            value_to_variant(new JSC.Value.boolean(this.context, false)).print(true),
            "false"
        );

        var value = new JSC.Value.array_from_garray(this.context, null);
        assert_equal(
            value_to_variant(value).print(true),
            "()"
        );

        var array = new GLib.GenericArray<JSC.Value>();
        array.add(new JSC.Value.string(this.context, "test"));
        value = new JSC.Value.array_from_garray(this.context, array);
        assert_equal(
            value_to_variant(value).print(true),
            "['test']"
        );

        array = new GLib.GenericArray<JSC.Value>();
        array.add(new JSC.Value.string(this.context, "test1"));
        array.add(new JSC.Value.string(this.context, "test2"));
        value = new JSC.Value.array_from_garray(this.context, array);
        assert_equal(
            value_to_variant(value).print(true),
            "['test1', 'test2']"
        );

        array = new GLib.GenericArray<JSC.Value>();
        array.add(new JSC.Value.string(this.context, "test"));
        array.add(new JSC.Value.boolean(this.context, true));
        value = new JSC.Value.array_from_garray(this.context, array);
        assert_equal(
            value_to_variant(value).print(true),
            "('test', true)"
        );

        value = new JSC.Value.object(this.context, null, null);
        assert_equal(
            value_to_variant(value).print(true),
            "@a{sv} {}"
        );
        value.object_set_property(
            "test", new JSC.Value.boolean(this.context, true)
        );
        assert_equal(
            value_to_variant(value).print(true),
            "{'test': <true>}"
        );
    }

    public void to_value() throws GLib.Error {
        var variant = new GLib.Variant.maybe(GLib.VariantType.STRING, null);
        var value = variant_to_value(this.context, variant);
        assert_true(value.is_null(), variant.print(true));

        variant = new GLib.Variant.string("test");
        value = variant_to_value(this.context, variant);
        assert_true(value.is_string(), variant.print(true));
        assert_equal(value.to_string(), "test", variant.print(true));

        variant = new GLib.Variant.int32(42);
        value = variant_to_value(this.context, variant);
        assert_true(value.is_number(), variant.print(true));
        assert_equal<int32?>(value.to_int32(), 42, variant.print(true));

        variant = new GLib.Variant.double(42.0);
        value = variant_to_value(this.context, variant);
        assert_true(value.is_number(), variant.print(true));
        assert_within(value.to_double(), 42.0, 0.0000001, variant.print(true));

        variant = new GLib.Variant.boolean(true);
        value = variant_to_value(this.context, variant);
        assert_true(value.is_boolean(), variant.print(true));
        assert_true(value.to_boolean(), variant.print(true));

        variant = new GLib.Variant.boolean(false);
        value = variant_to_value(this.context, variant);
        assert_true(value.is_boolean(), variant.print(true));
        assert_false(value.to_boolean(), variant.print(true));

        variant = new GLib.Variant.strv({"test"});
        value = variant_to_value(this.context, variant);
        assert_true(value.is_array(), variant.print(true));
        assert_true(
            value.object_get_property_at_index(0).is_string(),
            variant.print(true)
        );
        assert_equal(
            value.object_get_property_at_index(0).to_string(),
            "test",
            variant.print(true)
        );

        var dict = new GLib.VariantDict();
        variant = dict.end();
        value = variant_to_value(this.context, variant);
        assert_true(value.is_object(), variant.print(true));

        dict = new GLib.VariantDict();
        dict.insert_value("test", new GLib.Variant.boolean(true));
        variant = dict.end();
        value = variant_to_value(this.context, variant);
        assert_true(value.is_object(), variant.print(true));
        assert_true(
            value.object_get_property("test").is_boolean(),
            value.to_string()
        );
        assert_true(
            value.object_get_property("test").to_boolean(),
            value.to_string()
        );
    }
}
