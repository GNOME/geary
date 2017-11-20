/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Response for a NAMESPACE command.
 *
 * @see Geary.Imap.NamespaceCommand
 */
public class Geary.Imap.NamespaceResponse : BaseObject {


    public Gee.List<Namespace>? personal { get; private set; default = null; }
    public Gee.List<Namespace>? user { get; private set; default = null; }
    public Gee.List<Namespace>? shared { get; private set; default = null; }


    /**
     * Decodes {@link ServerData} into a NamespaceResponse representation.
     *
     * The ServerData must be the response to a NAMESPACE command.
     *
     * @see ServerData.get_list
     */
    public static NamespaceResponse decode(ServerData server_data) throws ImapError {
        StringParameter cmd = server_data.get_as_string(1);
        if (!cmd.equals_ci(NamespaceCommand.NAME))
            throw new ImapError.PARSE_ERROR(
                "Not NAMESPACE data: %s", server_data.to_string()
            );

        if (server_data.size <= 2) {
            throw new ImapError.PARSE_ERROR(
                "No NAMESPACEs provided: %s", server_data.to_string()
            );
        }

        ListParameter? personal = server_data.get_as_nullable_list(2);
        ListParameter? user = null;
        if (server_data.size >= 4) {
            user = server_data.get_as_nullable_list(3);
        }
        ListParameter? shared = null;
        if (server_data.size >= 5) {
            shared = server_data.get_as_nullable_list(4);
        }

        return new NamespaceResponse(
            parse_namespaces(personal),
            user != null ? parse_namespaces(user) : null,
            shared != null ? parse_namespaces(shared) : null
        );
    }

    private static Gee.List<Namespace>? parse_namespaces(ListParameter? list) throws ImapError {
        Gee.List<Namespace>? nss = null;
        if (list != null) {
            nss = new Gee.ArrayList<Namespace>();
            for (int i = 0; i < list.size; i++) {
                nss.add(parse_namespace(list.get_as_list(i)));
            }
        }
        return nss;
    }

    private static Namespace? parse_namespace(ListParameter? list) throws ImapError {
        Namespace? ns = null;
        if (list != null && list.size >= 1) {
            ns = new Namespace(
                list.get_as_string(0).ascii,
                list.get_as_nullable_string(1).nullable_ascii
            );
        }
        return ns;
    }

    public NamespaceResponse(Gee.List<Namespace>? personal, Gee.List<Namespace>? user, Gee.List<Namespace>? shared) {
        this.personal = personal;
        this.user = user;
        this.shared = shared;
    }

}
