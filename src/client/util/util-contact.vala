/*
 * Copyright 2022 Cédric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

namespace Util.Contact {

    /**
     * Returns true if loading images for contact is allowed
     */
    public bool should_load_images(Application.Contact contact, Application.Configuration config) {
        var email_addresses = contact.email_addresses;
        var domains = config.get_images_trusted_domains();
        if (contact == null) {
            return false;
        // Contact trusted
        } else if (contact.load_remote_resources) {
            return true;
        // All emails are trusted
        } else if (domains.length > 0 && domains[0] == "*") {
            return true;
        // Contact domain trusted
        } else {
            foreach (Geary.RFC822.MailboxAddress email in email_addresses) {
                if (email.domain in domains) {
                    return true;
                }
            }
        }
        return false;
    }
}
