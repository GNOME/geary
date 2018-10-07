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


    // Initiates and manages an avatar load using Gravatar
    private class AvatarLoader : Geary.BaseObject {

        internal Gdk.Pixbuf? avatar = null;
        internal Geary.Nonblocking.Semaphore lock =
            new Geary.Nonblocking.Semaphore();

        private string base_url;
        private Geary.RFC822.MailboxAddress address;
        private int pixel_size;


        internal AvatarLoader(Geary.RFC822.MailboxAddress address,
                              string base_url,
                              int pixel_size) {
            this.address = address;
            this.base_url = base_url;
            this.pixel_size = pixel_size;
        }

        internal async void load(Soup.Session session,
                                 Cancellable load_cancelled)
            throws GLib.Error {
            Error? workaround_err = null;
            if (!Geary.String.is_empty_or_whitespace(this.base_url)) {
                string md5 = GLib.Checksum.compute_for_string(
                    GLib.ChecksumType.MD5, this.address.address.strip().down()
                );
                Soup.Message message = new Soup.Message(
                    "GET",
                    "%s/%s?d=%s&s=%d".printf(
                        this.base_url, md5, "404", this.pixel_size
                    )
                );

                try {
                    // We want to just pass load_cancelled to send_async
                    // here, but per Bug 778720 this is causing some
                    // crashy race in libsoup's cache implementation, so
                    // for now just let the load go through and manually
                    // check to see if the load has been cancelled before
                    // setting the avatar
                    InputStream data = yield session.send_async(
                        message,
                        null // should be 'load_cancelled'
                    );
                    if (message.status_code == 200 &&
                        data != null &&
                        !load_cancelled.is_cancelled()) {
                        this.avatar = yield new Gdk.Pixbuf.from_stream_at_scale_async(
                            data, pixel_size, pixel_size, true, load_cancelled
                        );
                    }
                } catch (Error err) {
                    workaround_err = err;
                }
            }

            this.lock.blind_notify();

            if (workaround_err != null) {
                throw workaround_err;
            }
        }

    }


    private Configuration config;

    private Soup.Session session;
    private Soup.Cache cache;
    private Gee.Map<string,AvatarLoader> loaders =
        new Gee.HashMap<string,AvatarLoader>();


    public AvatarStore(Configuration config, GLib.File cache_root) {
        this.config = config;

        File avatar_cache_dir = cache_root.get_child("avatars");
        this.cache = new Soup.Cache(
            avatar_cache_dir.get_path(),
            Soup.CacheType.SINGLE_USER
        );
        this.cache.load();
        this.cache.set_max_size(16 * 1024 * 1024); // 16MB
        this.session = new Soup.Session();
        this.session.add_feature(this.cache);
    }

    public void close() {
        this.cache.flush();
        this.cache.dump();
    }

    public async Gdk.Pixbuf? load(Geary.RFC822.MailboxAddress address,
                                    int pixel_size,
                                    Cancellable load_cancelled)
        throws Error {
        string key = address.to_string();
        AvatarLoader loader = this.loaders.get(key);
        if (loader == null) {
            // Haven't started loading the avatar, so do it now
            loader = new AvatarLoader(
                address, this.config.avatar_url, pixel_size
            );
            this.loaders.set(key, loader);
            yield loader.load(this.session, load_cancelled);
        } else {
            // Load has already started, so wait for it to finish
            yield loader.lock.wait_async();
        }
        return loader.avatar;
    }

}
