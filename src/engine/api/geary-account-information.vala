/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.AccountInformation : Object {
    private const string GROUP = "AccountInformation";
    private const string REAL_NAME_KEY = "real_name";
    
    private File file;
    public string real_name { get; set; }
    
    public AccountInformation(File store_file, string real_name = "") {
        file = store_file;
        this.real_name = real_name;
    }
    
    public AccountInformation.from_file(File file) throws Error {
        this.file = file;
        KeyFile key_file = new KeyFile();
        try {
            key_file.load_from_file(file.get_path() ?? "", KeyFileFlags.NONE);
        } catch (FileError.NOENT err) {
            // The file didn't exist.  No big deal -- just means we give you the defaults.
        } finally {
            real_name = get_key_file_value(key_file, GROUP, REAL_NAME_KEY);
        }
    }
    
    private string get_key_file_value(KeyFile key_file, string group, string key, string _default = "") {
        string v = _default;
        try {
            v = key_file.get_value(group, key);
        } catch(KeyFileError err) {
            // Ignore.
        }
        return v;
    }
    
    public async void store_async(Cancellable? cancellable = null) throws Error {
        KeyFile key_file = new KeyFile();
        key_file.set_value(GROUP, REAL_NAME_KEY, real_name);
        string data = key_file.to_data();
        yield file.replace_contents_async(data, data.length, null, false, FileCreateFlags.NONE,
            cancellable);
    }
}
