/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Inet {

private const string HOST_PART_REGEX = """^(?!-)[\p{L}\p{N}-]{1,63}(?<!-)$""";
private const string IPv6_REGEX = """^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$|^(([a-zA-Z]|[a-zA-Z][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z]|[A-Za-z][A-Za-z0-9\-]*[A-Za-z0-9])$|^\s*((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?\s*$""";

/**
 * Formats a socket address as a "name:port" string.
 */
public string address_to_string(InetSocketAddress addr) {
    return "%s:%u".printf(addr.address.to_string(), addr.port);
}

/**
 * Determines if a string represents a valid host name or IP address.
 *
 * This function validates a host name or IP address for display,
 * i.e. without IDN or URI encoding. It simply performs a syntactic
 * check, it does not attempt to resolve the host name. Note that both
 * valid IPv4 addresses (such as "123.0.10.100") and invalid IPv4
 * addresses (such as "123" or "555.123.456.789") are valid host
 * names, so it is not possible to determine if an IPv4 address is
 * invalid.
 */
public bool is_valid_display_host(owned string? name) {
    bool is_valid = false;
    if (!Geary.String.is_empty(name)) {
        // Check for a valid host name validation here is a modified version of:
        // http://stackoverflow.com/questions/2532053/validate-a-hostname-string
        if (name.length <= 253) {
            if (name[name.length - 1] == '.')
                name = name[0:-1];
            try {
                Regex part_regex = new Regex(HOST_PART_REGEX);
                is_valid = true;
                foreach (string part in name.split(".")) {
                    if (!part_regex.match(part)) {
                        is_valid = false;
                        break;
                    }
                }
            } catch (Error err) {
                debug("Error validating as host name: %s", err.message);
            }
        }

        // Check for a IPv6 address
        if (!is_valid) {
            try {
                Regex address_regex = new Regex(
                    IPv6_REGEX, RegexCompileFlags.CASELESS
                );
                is_valid = address_regex.match(name);
            } catch (Error err) {
                debug("Error validating as IPv6 address: %s", err.message);
            }
        }
    }
    return is_valid;
}

}

