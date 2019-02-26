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


    private Folks.IndividualAggregator individuals;


    public AvatarStore(Folks.IndividualAggregator individuals) {
        this.individuals = individuals;
    }

    public void close() {
        // Noop
    }

    public async Gdk.Pixbuf? load(Geary.RFC822.MailboxAddress mailbox,
                                  int pixel_size,
                                  GLib.Cancellable cancellable)
        throws GLib.Error {
        Folks.SearchView view = new Folks.SearchView(
            this.individuals,
            new Folks.SimpleQuery(
                mailbox.address,
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

        Gdk.Pixbuf? pixbuf = null;
        if (match != null && match.avatar != null) {
            GLib.InputStream data = yield match.avatar.load_async(
                pixel_size, cancellable
            );
            pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(
                data, pixel_size, pixel_size, true, cancellable
            );
        }
        return pixbuf;
    }

}
