/*
 * Copyright 2016-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * Email address avatar loader and cache.
 *
 * Avatars are loaded from a {@link Contact} object's Folks individual
 * if present, else one will be generated using initials and
 * background colour based on the of the source mailbox's name if
 * present, or address. Avatars are cached at each requested logical
 * pixel size, per Folks individual and then per source mailbox
 * name. This strategy allows avatar bitmaps to reflect the desktop
 * address-book's user picture if present, else provide individualised
 * avatars, even for mail sent by software like Mailman and Discourse.
 *
 * Unlike {@link ContactStore}, once store instance is useful for
 * loading and caching avatars across accounts.
 */
internal class Application.AvatarStore : Geary.BaseObject {


    // Max size is low since most conversations don't get above the
    // low hundreds of messages, and those that do will likely get
    // many repeated participants
    private const uint MAX_CACHE_SIZE = 128;


    private class CacheEntry {


        public static string to_name_key(Geary.RFC822.MailboxAddress source) {
            // Use short name as the key, since it will use the name
            // first, then the email address, which is especially
            // important for things like GitLab email where the
            // address is always the same, but the name changes. This
            // ensures that each such user gets different initials.
            return source.to_short_display().normalize().casefold();
        }

        public Contact contact;
        public Geary.RFC822.MailboxAddress source;

        private Gee.List<Gdk.Pixbuf> pixbufs = new Gee.LinkedList<Gdk.Pixbuf>();


        public CacheEntry(Contact contact,
                          Geary.RFC822.MailboxAddress source) {
            this.contact = contact;
            this.source = source;

            contact.changed.connect(on_contact_changed);
        }

        ~CacheEntry() {
            this.contact.changed.disconnect(on_contact_changed);
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
                Folks.Individual? individual = contact.individual;
                if (individual != null &&
                    individual.avatar != null) {
                    GLib.InputStream data =
                        yield individual.avatar.load_async(
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
                if (this.contact.is_trusted) {
                    name = this.contact.display_name;
                } else {
                    // Use short display because it will clean up the
                    // string, use the name if present and fall back
                    // on the address if not.
                    name = this.source.to_short_display();
                }
                pixbuf = Util.Avatar.generate_user_picture(name, pixel_size);
                pixbuf = Util.Avatar.round_image(pixbuf);
                this.pixbufs.add(pixbuf);
            }

            return pixbuf;
        }

        private void on_contact_changed() {
            this.pixbufs.clear();
        }

    }


    // Folks cache used for storing contacts backed by a Folk
    // individual. This is the primary cache since we want to use the
    // details for avatar and display name lookup from the desktop
    // address-book if available.
    private Util.Cache.Lru<CacheEntry> folks_cache =
        new Util.Cache.Lru<CacheEntry>(MAX_CACHE_SIZE);

    // Name cache uses the source mailbox's short name as the key,
    // since this will make avatar initials match well. It is used to
    // cache avatars for contacts not saved in the desktop
    // address-book.
    private Util.Cache.Lru<CacheEntry> name_cache =
        new Util.Cache.Lru<CacheEntry>(MAX_CACHE_SIZE);


    /** Closes the store, flushing all caches. */
    public void close() {
        this.folks_cache.clear();
        this.name_cache.clear();
    }

    public async Gdk.Pixbuf? load(Contact contact,
                                  Geary.RFC822.MailboxAddress source,
                                  int pixel_size,
                                  GLib.Cancellable cancellable)
        throws GLib.Error {
        CacheEntry hit = null;
        if (contact.is_desktop_contact && contact.is_trusted) {
            string key = contact.individual.id;
            hit = this.folks_cache.get_entry(key);

            if (hit == null) {
                hit = new CacheEntry(contact, source);
                this.folks_cache.set_entry(key, hit);
            }
        }

        if (hit == null) {
            string key = CacheEntry.to_name_key(source);
            hit = this.name_cache.get_entry(key);

            if (hit == null) {
                hit = new CacheEntry(contact, source);
                this.name_cache.set_entry(key, hit);
            }
        }

        return yield hit.load(pixel_size, cancellable);
    }

}
