/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Geary offers a couple of places where the user may mark an object (email, contact)
 * with a named flag.  The presence of the flag indicates if the state is enabled/on
 * or disabled/off.
 */

public class Geary.NamedFlag : BaseObject, Gee.Hashable<Geary.NamedFlag> {
    public string name { get; private set; }

    public NamedFlag(string name) {
        this.name = name;
    }

    public bool equal_to(Geary.NamedFlag other) {
        if (this == other)
            return true;

        return name.down() == other.name.down();
    }

    public uint hash() {
        return name.down().hash();
    }

    public string serialise() {
        return name;
    }

    public string to_string() {
        return name;
    }
}
