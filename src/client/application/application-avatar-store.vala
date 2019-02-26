/*
 * Copyright 2016-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * Email address avatar loader and cache.
 */
public class Application.AvatarStore : Geary.BaseObject {


    // Max age is low since we really only want to cache between
    // conversation loads.
    private const int64 MAX_CACHE_AGE_US = 5 * 1000 * 1000;

    // Max size is low since most conversations don't get above the
    // low hundreds of messages, and those that do will likely get
    // many repeated participants
    private const uint MAX_CACHE_SIZE = 128;


    private class CacheEntry {


        public static int lru_compare(CacheEntry a, CacheEntry b) {
            return (a.address == b.address)
                ? 0 : (int) (a.last_used - b.last_used);
        }


        public string address;

        // Store nulls so we can also cache avatars not found
        public Folks.Individual? individual;

        public int64 last_used;

        private Gee.List<Gdk.Pixbuf> pixbufs = new Gee.LinkedList<Gdk.Pixbuf>();

        public CacheEntry(string address,
                          Folks.Individual? individual,
                          int64 last_used) {
            this.address = address;
            this.individual = individual;
            this.last_used = last_used;
        }

        public async Gdk.Pixbuf? load(int pixel_size,
                                      GLib.Cancellable cancellable)
            throws GLib.Error {
            Gdk.Pixbuf? pixbuf = null;
            foreach (Gdk.Pixbuf cached in this.pixbufs) {
                if ((cached.height == pixel_size && cached.width >= pixel_size) ||
                    (cached.width == pixel_size && cached.height >= pixel_size)) {
                    pixbuf = cached;
                    break;
                }
            }

            if (pixbuf == null) {
                Folks.Individual? individual = this.individual;
                if (individual != null && individual.avatar != null) {
                    GLib.InputStream data = yield individual.avatar.load_async(
                        pixel_size, cancellable
                    );
                    pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(
                        data, pixel_size, pixel_size, true, cancellable
                    );
                    this.pixbufs.add(pixbuf);
                }
            }
            return pixbuf;
        }

    }


    private Folks.IndividualAggregator individuals;
    private Gee.Map<string,CacheEntry> lru_cache =
        new Gee.HashMap<string,CacheEntry>();
    private Gee.SortedSet<CacheEntry> lru_ordering =
        new Gee.TreeSet<CacheEntry>(CacheEntry.lru_compare);


    public AvatarStore(Folks.IndividualAggregator individuals) {
        this.individuals = individuals;
    }

    public void close() {
        this.lru_cache.clear();
        this.lru_ordering.clear();
    }

    public async Gdk.Pixbuf? load(Geary.RFC822.MailboxAddress mailbox,
                                  int pixel_size,
                                  GLib.Cancellable cancellable)
        throws GLib.Error {
        // Normalise the address to improve caching
        CacheEntry match = yield get_match(
            mailbox.address.normalize().casefold()
        );
        return yield match.load(pixel_size, cancellable);
    }


    private async CacheEntry get_match(string address)
        throws GLib.Error {
        int64 now = GLib.get_monotonic_time();
        CacheEntry? entry = this.lru_cache.get(address);
        if (entry != null) {
            if (entry.last_used + MAX_CACHE_AGE_US >= now) {
                // Need to remove the entry from the ordering before
                // updating the last used time since doing so changes
                // the ordering
                this.lru_ordering.remove(entry);
                entry.last_used = now;
                this.lru_ordering.add(entry);
            } else {
                this.lru_cache.unset(address);
                this.lru_ordering.remove(entry);
                entry = null;
            }
        }

        if (entry == null) {
            Folks.Individual? match = yield search_match(address);
            entry = new CacheEntry(address, match, now);
            this.lru_cache.set(address, entry);
            this.lru_ordering.add(entry);

            // Prune the cache if needed
            if (this.lru_cache.size > MAX_CACHE_SIZE) {
                CacheEntry oldest = this.lru_ordering.first();
                this.lru_cache.unset(oldest.address);
                this.lru_ordering.remove(oldest);
            }
        }

        return entry;
    }

    private async Folks.Individual? search_match(string address)
        throws GLib.Error {
        Folks.SearchView view = new Folks.SearchView(
            this.individuals,
            new Folks.SimpleQuery(
                address,
                new string[] {
                    Folks.PersonaStore.detail_key(
                        Folks.PersonaDetail.EMAIL_ADDRESSES
                    )
                }
            )
        );

        yield view.prepare();

        Folks.Individual? match = null;
        if (!view.individuals.is_empty) {
            match = view.individuals.first();
        }

        try {
            yield view.unprepare();
        } catch (GLib.Error err) {
            warning("Error unpreparing Folks search: %s", err.message);
        }

        return match;
    }

}
