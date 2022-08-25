/*
 * Copyright 2022 Cédric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Thunderbird autoconfig XML values
 */
internal class Accounts.AutoConfigValues {
    // emailProvider.id
    public string id { get; set; default = ""; }

    // incomingServer[type="imap"].hostname
    public string imap_server { get; set; default = ""; }
    // incomingServer[type="imap"].port
    public string imap_port { get; set; default = ""; }
    // incomingServer[type="imap"].socketType
    public Geary.TlsNegotiationMethod imap_tls_method {
        get; set; default = Geary.TlsNegotiationMethod.TRANSPORT;
    }

    // outgoingServer[type="smtp"].hostname
    public string smtp_server{ get; set; default = ""; }
    // outgoingServer[type="smtp"].port
    public string smtp_port { get; set; default = ""; }
    // outgoingServer[type="smtp"].socketType
    public Geary.TlsNegotiationMethod smtp_tls_method {
        get; set; default = Geary.TlsNegotiationMethod.TRANSPORT;
    }

}

internal errordomain Accounts.AutoConfigError {
    ERROR
}

/**
 * An account autoconfiguration helper
 */
internal class Accounts.AutoConfig {

    private static string AUTOCONFIG_BASE_URI = "https://autoconfig.thunderbird.net/v1.1/";
    private static string AUTOCONFIG_PATH = "/mail/config-v1.1.xml";

    private unowned GLib.Cancellable cancellable;

    internal AutoConfig(GLib.Cancellable auto_config_cancellable) {
        cancellable = auto_config_cancellable;
    }

    public async AutoConfigValues get_config(string hostname)
            throws AutoConfigError {
        AutoConfigValues auto_config_values;

        // First try to get config from mail domain, then from thunderbird
        try {
            auto_config_values = yield get_config_for_uri(
                "https://autoconfig." + hostname + AUTOCONFIG_PATH
            );
        } catch (AutoConfigError err) {
            auto_config_values = yield get_config_for_uri(
                AUTOCONFIG_BASE_URI + hostname
            );
        }
        return auto_config_values;
    }

    private async AutoConfigValues get_config_for_uri(string uri)
            throws AutoConfigError {
        GLib.InputStream stream;
        var session = new Soup.Session();
        var msg = new Soup.Message("GET", uri);

        try {
            stream = yield session.send_async(
                msg, Priority.DEFAULT, this.cancellable
            );
        } catch (GLib.Error err) {
            throw new AutoConfigError.ERROR(err.message);
        }

        try {
            var stdout_stream = new MemoryOutputStream.resizable();
            yield stdout_stream.splice_async(
                stream, 0, Priority.DEFAULT, null
            );
            stdout_stream.write("\0".data);
            stdout_stream.close();
            unowned var xml_data = (string) stdout_stream.get_data();
            return get_config_for_xml(xml_data);
        } catch (GLib.Error err) {
            throw new AutoConfigError.ERROR(err.message);
        } finally {
            try {
                yield stream.close_async();
            } catch (GLib.Error err) {
                // Oh well
            }
        }
    }

    private AutoConfigValues get_config_for_xml(string xml_data)
            throws AutoConfigError {
        unowned Xml.Doc doc = Xml.Parser.parse_memory(xml_data, xml_data.length);
        if (doc == null) {
            throw new AutoConfigError.ERROR("Invalid XML");
        }

        unowned Xml.Node root = doc.get_root_element();
        unowned Xml.Node email_provider = get_node(root, "emailProvider");
        unowned Xml.Node incoming_server = get_node(email_provider, "incomingServer");
        unowned Xml.Node outgoing_server = get_node(email_provider, "outgoingServer");

        if (incoming_server == null || outgoing_server == null) {
            throw new AutoConfigError.ERROR("Invalid XML");
        }

        if (incoming_server.get_prop("type") != "imap" ||
                outgoing_server.get_prop("type") != "smtp") {
            throw new AutoConfigError.ERROR("Unsupported protocol");
        }

        var auto_config_values = new AutoConfigValues();

        auto_config_values.id = email_provider.get_prop("id");

        auto_config_values.imap_server = get_node_value(incoming_server, "hostname");
        auto_config_values.imap_port = get_node_value(incoming_server, "port");
        auto_config_values.imap_tls_method = get_tls_method(
            get_node_value(incoming_server, "socketType")
        );

        auto_config_values.smtp_server = get_node_value(outgoing_server, "hostname");
        auto_config_values.smtp_port = get_node_value(outgoing_server, "port");
        auto_config_values.smtp_tls_method = get_tls_method(
            get_node_value(outgoing_server, "socketType")
        );

        return auto_config_values;
    }

    private unowned Xml.Node? get_node(Xml.Node root, string name) {
        for (unowned Xml.Node entry = root.children; entry != null; entry = entry.next) {
            if (entry.type == Xml.ElementType.ELEMENT_NODE && entry.name == name) {
                return entry;
            }
        }
        return null;
    }

    private string get_node_value(Xml.Node root, string name) {
        unowned Xml.Node? node = get_node(root, name);
        if (node == null)
          return "";
        return node.get_content();
    }

    private Geary.TlsNegotiationMethod get_tls_method(string method) {
        switch (method) {
        case "SSL":
            return Geary.TlsNegotiationMethod.TRANSPORT;
        case "STARTTLS":
            return Geary.TlsNegotiationMethod.START_TLS;
        default:
            return Geary.TlsNegotiationMethod.NONE;
        }
    }
}
