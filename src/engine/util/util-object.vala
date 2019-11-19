/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.ObjectUtils {

/**
 * Creates a set of property bindings from source to dest with the given binding flags.
 */
public Gee.List<Binding>? mirror_properties(Object source, Object dest, BindingFlags
    flags = GLib.BindingFlags.DEFAULT | GLib.BindingFlags.SYNC_CREATE) {
    // Make sets of both object's properties.
    Gee.HashSet<ParamSpec> source_properties =
        iterate_array(source.get_class().list_properties()).to_hash_set();
    Gee.HashSet<ParamSpec> dest_properties =
        iterate_array(dest.get_class().list_properties()).to_hash_set();

    // Remove properties from source_properties that are not in both sets.
    source_properties.retain_all(dest_properties);

    // Create all bindings.
    Gee.List<Binding> bindings = new Gee.ArrayList<Binding>();
    foreach(ParamSpec ps in source_properties) {
        if ((ps.flags & ParamFlags.WRITABLE) != 0)
            bindings.add(source.bind_property(ps.name, dest, ps.name, flags));
    }

    return bindings.size > 0 ? bindings : null;
}

/**
 * Removes a property mirror created by mirror_properties
 */
public void unmirror_properties(Gee.List<Binding> bindings) {
    foreach(Binding b in bindings)
        b.unref();

    bindings.clear();
}

/** Convenience method for getting an enum value's nick name. */
public string to_enum_nick<E>(GLib.Type type, E value) {
    GLib.EnumClass enum_type = (GLib.EnumClass) type.class_ref();
    return enum_type.get_value((int) value).value_nick;
}

/** Convenience method for getting an enum value's from its nick name. */
public E from_enum_nick<E>(GLib.Type type, string nick) throws EngineError {
    GLib.EnumClass enum_type = (GLib.EnumClass) type.class_ref();
    unowned GLib.EnumValue? e_value = enum_type.get_value_by_nick(nick);
    if (e_value == null) {
        throw new EngineError.BAD_PARAMETERS(
            "Unknown %s enum value: %s", typeof(E).name(), nick
        );
    }
    return (E) e_value.value;
}

}
