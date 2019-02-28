/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public delegate uint Geary.State.Transition(uint state, uint event, void *user = null,
    Object? object = null, Error? err = null);

public delegate void Geary.State.PostTransition(void *user = null, Object? object = null,
    Error? err = null);

public class Geary.State.Mapping : BaseObject {
    public uint state;
    public uint event;
    public unowned Transition transition;

    public Mapping(uint state, uint event, Transition transition) {
        this.state = state;
        this.event = event;
        this.transition = transition;
    }
}

namespace Geary.State {

// A utility Transition for nop transitions (i.e. it merely returns the state passed in).
public uint nop(uint state, uint event) {
    return state;
}

}
