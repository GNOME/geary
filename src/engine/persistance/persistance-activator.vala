/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An Activator is responsible for mapping a class name to a class and activating (instantiating)
 * it on-demand.
 */

public interface Geary.Persistance.Activator : Object {
    /**
     * Returns an instance of {@link Serializable} that maps to the persisted classname and version
     * number.
     *
     * If unknown or unable to create an instance for the version number, return null.
     */
    public abstract Serializable? activate(string classname, int version);
}

