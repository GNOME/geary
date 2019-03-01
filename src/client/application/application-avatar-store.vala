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


        public static string to_key(Geary.RFC822.MailboxAddress mailbox) {
            // Use short name as the key, since it will use the name
            // first, then the email address, which is especially
            // important for things like GitLab email where the
            // address is always the same, but the name changes. This
            // ensures that each such user gets different initials.
            return mailbox.to_short_display().normalize().casefold();
        }

        public static int lru_compare(CacheEntry a, CacheEntry b) {
            return (a.key == b.key)
                ? 0 : (int) (a.last_used - b.last_used);
        }


        public string key;

        public Geary.RFC822.MailboxAddress mailbox;

        // Store nulls so we can also cache avatars not found
        public Folks.Individual? individual;

        public int64 last_used;

        private Gee.List<Gdk.Pixbuf> pixbufs = new Gee.LinkedList<Gdk.Pixbuf>();

        public CacheEntry(Geary.RFC822.MailboxAddress mailbox,
                          Folks.Individual? individual,
                          int64 last_used) {
            this.key = to_key(mailbox);
            this.mailbox = mailbox;
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
                    pixbuf = Util.Avatar.round_image(pixbuf);
                    this.pixbufs.add(pixbuf);
                }
            }

            if (pixbuf == null) {
                string? name = null;
                // XXX should really be using the folks display name
                // here as below, but since we should the name from
                // the email address if present in
                // ConversationMessage, and since that might not match
                // the folks display name, it is confusing when the
                // initials are one thing and the name is
                // another. Re-enable below when we start using the
                // folks display name in ConversationEmail
                name = this.mailbox.to_short_display();
                // if (this.individual != null) {
                //     name = this.individual.display_name;
                // } else {
                //     // Use short display because it will clean up the
                //     // string, use the name if present and fall back
                //     // on the address if not.
                //     name = this.mailbox.to_short_display();
                // }
                pixbuf = Util.Avatar.generate_user_picture(name, pixel_size);
                pixbuf = Util.Avatar.round_image(pixbuf);
                this.pixbufs.add(pixbuf);
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
        CacheEntry match = yield get_match(mailbox);
        return yield match.load(pixel_size, cancellable);
    }


    private async CacheEntry get_match(Geary.RFC822.MailboxAddress mailbox)
        throws GLib.Error {
        string key = CacheEntry.to_key(mailbox);
        int64 now = GLib.get_monotonic_time();
        CacheEntry? entry = this.lru_cache.get(key);
        if (entry != null) {
            if (entry.last_used + MAX_CACHE_AGE_US >= now) {
                // Need to remove the entry from the ordering before
                // updating the last used time since doing so changes
                // the ordering
                this.lru_ordering.remove(entry);
                entry.last_used = now;
                this.lru_ordering.add(entry);
            } else {
                this.lru_cache.unset(key);
                this.lru_ordering.remove(entry);
                entry = null;
            }
        }

        if (entry == null) {
            Folks.Individual? match = yield search_match(mailbox.address);
            entry = new CacheEntry(mailbox, match, now);
            this.lru_cache.set(key, entry);
            this.lru_ordering.add(entry);

            // Prune the cache if needed
            if (this.lru_cache.size > MAX_CACHE_SIZE) {
                CacheEntry oldest = this.lru_ordering.first();
                this.lru_cache.unset(oldest.key);
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
