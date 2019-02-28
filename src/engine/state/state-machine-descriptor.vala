/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public delegate string Geary.State.StateEventToString(uint state_or_event);

public class Geary.State.MachineDescriptor : BaseObject {
    public string name { get; private set; }
    public uint start_state { get; private set; }
    public uint state_count { get; private set; }
    public uint event_count { get; private set; }

    private unowned StateEventToString? state_to_string;
    private unowned StateEventToString? event_to_string;

    public MachineDescriptor(string name, uint start_state, uint state_count, uint event_count,
        StateEventToString? state_to_string, StateEventToString? event_to_string) {
        this.name = name;
        this.start_state = start_state;
        this.state_count = state_count;
        this.event_count = event_count;
        this.state_to_string = state_to_string;
        this.event_to_string = event_to_string;

        // starting state should be valid
        assert(start_state < state_count);
    }

    public string get_state_string(uint state) {
        return (state_to_string != null) ? state_to_string(state) : "%s STATE %u".printf(name, state);
    }

    public string get_event_string(uint event) {
        return (event_to_string != null) ? event_to_string(event) : "%s EVENT %u".printf(name, event);
    }
}

