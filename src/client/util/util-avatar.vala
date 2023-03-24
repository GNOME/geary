/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

namespace Util.Avatar {

    // The following was based on code written by Felipe Borges for
    // gnome-control-enter in panels/user-accounts/user-utils.c commit
    // 02c288ab6f069a0c106323a93400f192a63cb67e. The copyright in that
    // file is: "Copyright 2009-2010  Red Hat, Inc,"

    public void generate_user_picture(string name, GLib.MemoryInputStream stream) {
        Cairo.Surface surface = new Cairo.ImageSurface(
            Cairo.Format.ARGB32,
            Application.Client.AVATAR_SIZE_PIXELS,
            Application.Client.AVATAR_SIZE_PIXELS
        );
        Cairo.Context cr = new Cairo.Context(surface);
        cr.rectangle(0, 0,
                     Application.Client.AVATAR_SIZE_PIXELS,
                     Application.Client.AVATAR_SIZE_PIXELS);

        /* Fill the background with a colour for the name */
        Gdk.RGBA color = get_color_for_name(name);
        cr.set_source_rgb(
            color.red / 255.0, color.green / 255.0, color.blue / 255.0
        );
        cr.fill();

        /* Draw the initials on top */
        string? initials = extract_initials_from_name(name);
        if (initials != null) {
            string font = "Sans %d".printf(
                (int) GLib.Math.ceil(
                    Application.Client.AVATAR_SIZE_PIXELS / 4
                )
            );

            cr.set_source_rgb(1.0, 1.0, 1.0);
            Pango.Layout layout = Pango.cairo_create_layout(cr);
            layout.set_text(initials, -1);
            layout.set_font_description(Pango.FontDescription.from_string(font));

            int width, height;
            layout.get_size(out width, out height);
            cr.translate(Application.Client.AVATAR_SIZE_PIXELS / 2,
                         Application.Client.AVATAR_SIZE_PIXELS / 2);
            cr.move_to(
                -((double) width / Pango.SCALE) / 2,
                -((double) height / Pango.SCALE) / 2
            );
            Pango.cairo_show_layout(cr, layout);
        }

        surface.write_to_png_stream((data) => {
            stream.add_data(data);
            return Cairo.Status.SUCCESS;
        });
    }

    public string? extract_initials_from_name(string name) {
        string normalized = name.strip().normalize(-1, DEFAULT_COMPOSE);
        string? initials = null;
        if (normalized != "") {
            GLib.StringBuilder buf = new GLib.StringBuilder();
            unichar c = 0;
            int index  = 0;

            // Get the first alphanumeric char of the string
            for (int i = 0; normalized.get_next_char(ref index, out c); i++) {
                if (c.isalnum()) {
                    buf.append_unichar(c.toupper());
                    break;
                }
            }

            var split = normalized.split(" ");
            var reversed = new GLib.List<string>();
            foreach (string word in split[1:]) {
               reversed.prepend(word);
            }

            foreach (var word in reversed) {
                index = 0;
                word.get_next_char(ref index, out c);
                // If first char is alphanumeric, here we go, use it
                if (c.isalnum()) {
                    if (buf.len > 1) {
                        buf.erase (1, 1);
                    }
                    buf.append_unichar(c.toupper());
                    break;
                }
                // Otherwise search deeper in string
                index = 1;
                for (int i = 0; word.get_next_char(ref index, out c); i++) {
                    if (c.isalnum()) {
                        if (buf.len > 1) {
                            buf.erase (1, 1);
                        }
                        buf.append_unichar(c.toupper());
                        break;
                    }
                }
            }

            if (buf.data.length > 0) {
                initials = (string) buf.data;
            }
        }
        return initials;
    }


    public Gdk.RGBA get_color_for_name(string name) {
        // https://gitlab.gnome.org/Community/Design/HIG-app-icons/blob/master/GNOME%20HIG.gpl
        const double[,] GNOME_COLOR_PALETTE = {
            {  98, 160, 234 },
            {  53, 132, 228 },
            {  28, 113, 216 },
            {  26,  95, 180 },
            {  87, 227, 137 },
            {  51, 209, 122 },
            {  46, 194, 126 },
            {  38, 162, 105 },
            { 248, 228,  92 },
            { 246, 211,  45 },
            { 245, 194,  17 },
            { 229, 165,  10 },
            { 255, 163,  72 },
            { 255, 120,   0 },
            { 230,  97,   0 },
            { 198,  70,   0 },
            { 237,  51,  59 },
            { 224,  27,  36 },
            { 192,  28,  40 },
            { 165,  29,  45 },
            { 192,  97, 203 },
            { 163,  71, 186 },
            { 129,  61, 156 },
            {  97,  53, 131 },
            { 181, 131,  90 },
            { 152, 106,  68 },
            { 134,  94,  60 },
            {  99,  69,  44 }
        };

        Gdk.RGBA color = { 255, 255, 255, 1.0 };
        uint hash;
        uint number_of_colors;
        uint idx;

        if (name == "") {
            return color;
        }

        hash = name.hash();
        number_of_colors = GNOME_COLOR_PALETTE.length[0];
        idx = hash % number_of_colors;

        color.red   = GNOME_COLOR_PALETTE[idx,0];
        color.green = GNOME_COLOR_PALETTE[idx,1];
        color.blue  = GNOME_COLOR_PALETTE[idx,2];

        return color;
    }

}

