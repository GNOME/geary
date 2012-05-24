/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.AccountInformation : Object {
    private const string GROUP = "AccountInformation";
    private const string REAL_NAME_KEY = "real_name";
    private const string SERVICE_PROVIDER_KEY = "service_provider";
    private const string IMAP_HOST = "imap_host";
    private const string IMAP_PORT = "imap_port";
    private const string IMAP_SSL = "imap_ssl";
    private const string IMAP_PIPELINE = "imap_pipeline";
    private const string SMTP_HOST = "smtp_host";
    private const string SMTP_PORT = "smtp_port";
    private const string SMTP_SSL = "smtp_ssl";
    
    internal File? file = null;
    public string real_name { get; set; }
    public Geary.ServiceProvider service_provider { get; set; }
    
    public string imap_server_host { get; set; default = ""; }
    public uint16 imap_server_port { get; set; default = Imap.ClientConnection.DEFAULT_PORT_SSL; }
    public bool imap_server_ssl { get; set; default = true; }
    public bool imap_server_pipeline { get; set; default = true; }
    
    public string smtp_server_host { get; set; default = ""; }
    public uint16 smtp_server_port { get; set; default = Smtp.ClientConnection.DEFAULT_PORT_SSL; }
    public bool smtp_server_ssl { get; set; default = true; }
    
    public AccountInformation() {
    }
    
    public AccountInformation.from_file(File file) throws Error {
        this.file = file;
        KeyFile key_file = new KeyFile();
        try {
            key_file.load_from_file(file.get_path() ?? "", KeyFileFlags.NONE);
        } catch (FileError.NOENT err) {
            // The file didn't exist.  No big deal -- just means we give you the defaults.
        } finally {
            real_name = get_string_value(key_file, GROUP, REAL_NAME_KEY);
            service_provider = Geary.ServiceProvider.from_string(get_string_value(key_file, GROUP,
                SERVICE_PROVIDER_KEY));
            
            imap_server_host = get_string_value(key_file, GROUP, IMAP_HOST);
            imap_server_port = get_uint16_value(key_file, GROUP, IMAP_PORT,
                Imap.ClientConnection.DEFAULT_PORT_SSL);
            imap_server_ssl = get_bool_value(key_file, GROUP, IMAP_SSL, true);
            imap_server_pipeline = get_bool_value(key_file, GROUP, IMAP_PIPELINE, true);
            
            smtp_server_host = get_string_value(key_file, GROUP, SMTP_HOST);
            smtp_server_port = get_uint16_value(key_file, GROUP, SMTP_PORT,
                Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL);
            smtp_server_ssl = get_bool_value(key_file, GROUP, SMTP_SSL, true);
        }
    }
    
    private string get_string_value(KeyFile key_file, string group, string key, string _default = "") {
        string v = _default;
        try {
            v = key_file.get_value(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        return v;
    }
    
    private bool get_bool_value(KeyFile key_file, string group, string key, bool _default = false) {
        bool v = _default;
        try {
            v = key_file.get_boolean(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        return v;
    }
    
    private uint16 get_uint16_value(KeyFile key_file, string group, string key, uint16 _default = 0) {
        uint16 v = _default;
        try {
            v = (uint16) key_file.get_integer(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        return v;
    }
    
    public async void store_async(Cancellable? cancellable = null) throws Error {
        assert(file != null);
        
        yield file.create_async(FileCreateFlags.REPLACE_DESTINATION);
        
        KeyFile key_file = new KeyFile();
        
        key_file.set_value(GROUP, REAL_NAME_KEY, real_name);
        key_file.set_value(GROUP, SERVICE_PROVIDER_KEY, service_provider.to_string());
        
        key_file.set_value(GROUP, IMAP_HOST, imap_server_host);
        key_file.set_integer(GROUP, IMAP_PORT, imap_server_port);
        key_file.set_boolean(GROUP, IMAP_SSL, imap_server_ssl);
        key_file.set_boolean(GROUP, IMAP_PIPELINE, imap_server_pipeline);
        
        key_file.set_value(GROUP, SMTP_HOST, smtp_server_host);
        key_file.set_integer(GROUP, SMTP_PORT, smtp_server_port);
        key_file.set_boolean(GROUP, SMTP_SSL, smtp_server_ssl);
        
        string data = key_file.to_data();
        string new_etag;
        yield file.replace_contents_async(data.data, null, false, FileCreateFlags.NONE,
            cancellable, out new_etag);
    }
}
