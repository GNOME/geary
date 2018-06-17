/*
 * Copyright 2018 Michael James Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A simple ini-file-like configuration file.
 *
 * This class provides a convenient, high-level API for the {@link
 * GLib.KeyFile} class.
 */
public class Geary.ConfigFile {


    /**
     * A set of configuration keys grouped under a "[Name]" heading.
     */
    public class Group {


        private struct GroupLookup {
            string group;
            string prefix;

            public GroupLookup(string group, string prefix) {
                this.group = group;
                this.prefix = prefix;
            }
        }


        /** The config file this group was obtained from. */
        public ConfigFile file { get; private set; }

        /** The name of this group, as specified by a [Name] heading. */
        public string name { get; private set; }

        /** Determines if this group already exists in the config or not. */
        public bool exists {
            get { return this.backing.has_group(this.name); }
        }

        private GLib.KeyFile backing;
        private GroupLookup[] lookups;


        internal Group(ConfigFile file, string name, GLib.KeyFile backing) {
            this.file = file;
            this.name = name;
            this.backing = backing;

            this.lookups = { GroupLookup(name, "") };
        }


        /**
         * Sets a fallback lookup for missing keys in the group.
         *
         * This provides a fallback for looking up a legacy key. If
         * set, when performing a lookup for `key` and no such key in
         * the group is found, a lookup in the alternative specified
         * group for `prefix` + `key` will be performed and returned
         * if found.
         */
        public void set_fallback(string group, string prefix) {
            this.lookups = { this.lookups[0], GroupLookup(group, prefix) };
        }

        /** Determines if this group as a specific config key set. */
        public bool has_key(string name) {
            try {
                return this.backing.has_key(this.name, name);
            } catch (GLib.Error err) {
                return false;
            }
        }

        public string get_string(string key, string def = "") {
            string ret = def;
            foreach (GroupLookup lookup in this.lookups) {
                try {
                    ret = this.backing.get_value(
                        lookup.group, lookup.prefix + key
                    );
                    break;
                } catch (GLib.KeyFileError err) {
                    // continue
                }
            }
            return ret;
        }

        public void set_string(string key, string value) {
            this.backing.set_value(this.name, key, value);
        }

        public string get_escaped_string(string key, string def = "") {
            string ret = def;
            foreach (GroupLookup lookup in this.lookups) {
                try {
                    ret = this.backing.get_string(
                        lookup.group, lookup.prefix + key
                    );
                    break;
                } catch (GLib.KeyFileError err) {
                    // continue
                }
            }
            return ret;
        }

        public void set_escaped_string(string key, string value) {
            this.backing.set_string(this.name, key, value);
        }

        public Gee.List<string> get_string_list(string key) {
            try {
                string[] list = this.backing.get_string_list(this.name, key);
                if (list.length > 0)
                    return Geary.Collection.array_list_wrap<string>(list);
            } catch (GLib.KeyFileError err) {
                // Oh well
            }
            return new Gee.ArrayList<string>();
        }

        public void set_string_list(string key, Gee.List<string> value) {
            this.backing.set_string_list(this.name, key, value.to_array());
        }

        public bool get_bool(string key, bool def = false) {
            bool ret = def;
            foreach (GroupLookup lookup in this.lookups) {
                try {
                    ret = this.backing.get_boolean(
                        lookup.group, lookup.prefix + key
                    );
                    break;
                } catch (GLib.KeyFileError err) {
                    // continue
                }
            }
            return ret;
        }

        public void set_bool(string key, bool value) {
            this.backing.set_boolean(this.name, key, value);
        }

        public int get_int(string key, int def = 0) {
            int ret = def;
            foreach (GroupLookup lookup in this.lookups) {
                try {
                    ret = this.backing.get_integer(
                        lookup.group, lookup.prefix + key
                    );
                    break;
                } catch (GLib.KeyFileError err) {
                    // continue
                }
            }
            return ret;
        }

        public void set_int(string key, int value) {
            this.backing.set_integer(this.name, key, value);
        }

        public uint16 get_uint16(string key, uint16 def = 0) {
            return (uint16) get_int(key, (int) def);
        }

        public void set_uint16(string key, uint16 value) {
            this.backing.set_integer(this.name, key, (int) value);
        }

        /** Removes a key from this group. */
        public void remove_key(string name) throws GLib.Error {
            this.backing.remove_key(this.name, name);
        }

        /** Removes this group from the config file. */
        public void remove() throws GLib.Error {
            this.backing.remove_group(this.name);
        }

    }


    private GLib.File config_file;
    private GLib.KeyFile backing = new KeyFile();


    /**
     * Constructs a config file using the specified on-disk file.
     */
    public ConfigFile(GLib.File config_file) {
        this.config_file = config_file;
    }

    /**
     * Returns the config key group under the given heading name.
     *
     * If the group does not already exist, it will be created when a
     * key is first set, but an error will be thrown if a value is
     * accessed from it before doing so. Use {@link Group.exists} to
     * determine if the group has previously been created.
     */
    public Group get_group(string name) throws GLib.Error {
        return new Group(this, name, this.backing);
    }

    /**
     * Loads config data from the underlying config file.
     */
    public async void load(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        GLib.Error? thrown = null;
        yield Nonblocking.Concurrent.global.schedule_async(() => {
                try {
                    this.backing.load_from_file(
                        this.config_file.get_path(), KeyFileFlags.NONE
                    );
                } catch (GLib.Error err) {
                    thrown = err;
                }
            }, cancellable);
        if (thrown != null) {
            throw thrown;
        }
    }

    /**
     * Saves config data to the underlying config file.
     */
    public async void save(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        GLib.Error? thrown = null;
        yield Nonblocking.Concurrent.global.schedule_async(() => {
                try {
                    this.backing.save_to_file(this.config_file.get_path());
                } catch (GLib.Error err) {
                    thrown = err;
                }
            }, cancellable);
        if (thrown != null) {
            throw thrown;
        }
    }

}
