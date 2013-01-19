/*
 * src/project.vala
 * Copyright (C) 2012, 2013, Valama development team
 *
 * Valama is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Valama is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

using Vala;
using GLib;
using Gee;
using Xml;
using Gtk;
using Pango; // fonts

public class ValamaProject {
    public Guanako.Project guanako_project { get; private set; }
    public string project_path { get; private set; }
    public string project_file { get; private set; }
    public string[] project_source_dirs { get; private set; default = {"src"}; }
    public string[] project_source_files { get; private set; }
    public string[] project_buildsystem_dirs { get; private set; default = {"cmake"}; }
    public string[] project_buildsystem_files { get; private set; default = {"CMakeLists.txt"}; }
    public int version_major;
    public int version_minor;
    public int version_patch;
    public string project_name = _("valama_project");

    //TODO: Use sorted list.
    public Gee.ArrayList<string> files { get; private set; }
    public Gee.ArrayList<string> b_files { get; private set; }

    //TODO: Do we need an __ordered__ list? Gtk has already focus handling.
    private Gee.LinkedList<ViewMap?> vieworder;
    private TestProvider comp_provider;

    public ValamaProject (string project_file) throws LoadingError {
        var proj_file = File.new_for_path (project_file);
        this.project_file = proj_file.get_path();
        project_path = proj_file.get_parent().get_path();

        guanako_project = new Guanako.Project();
        files = new Gee.ArrayList<string>();
        b_files = new Gee.ArrayList<string>();

        stdout.printf (_("Load project file: %s\n"), this.project_file);
        load_project_file();  // can throw LoadingError

        generate_file_list (project_source_dirs,
                            project_source_files,
                            add_source_file);
        files.sort();
        generate_file_list (project_buildsystem_dirs,
                            project_buildsystem_files,
                            add_buildsystem_file);
        b_files.sort();

        guanako_project.update();

        vieworder = new Gee.LinkedList<ViewMap?>();

        /* Completion provider. */
        this.comp_provider = new TestProvider();
        this.comp_provider.priority = 1;
        this.comp_provider.name = _("Test Provider 1");
    }

    private void add_source_file (string filename) {
        if (!(filename.has_suffix (".vala") || filename.has_suffix (".vapi")))
            return;
        stdout.printf (_("Found file %s\n"), filename);
        if (!this.files.contains (filename)) {
            guanako_project.add_source_file_by_name (filename);
            this.files.add (filename);
        }
    }

    private void add_buildsystem_file (string filename) {
        if (!(filename.has_suffix (".cmake") || Path.get_basename (filename) == ("CMakeLists.txt")))
            return;
        stdout.printf (_("Found file %s\n"), filename);
        if (!this.b_files.contains (filename))
            this.b_files.add (filename);
    }

    private delegate void FileCallback (string filename);
    /**
     * Iterate over directories and files and fill list.
     */
    private void generate_file_list(string[] directories,
                           string[] files,
                           FileCallback? action = null) {
        try {
            File directory;
            FileEnumerator enumerator;
            FileInfo file_info;

            foreach (string dir in directories) {
                directory = File.new_for_path (Path.build_path (Path.DIR_SEPARATOR_S, project_path, dir));
                enumerator = directory.enumerate_children (FileAttribute.STANDARD_NAME, 0);

                while ((file_info = enumerator.next_file()) != null) {
                    action (Path.build_path (Path.DIR_SEPARATOR_S,
                                             project_path,
                                             dir,
                                             file_info.get_name()));
                }
            }

            foreach (string filename in files) {
                var path = Path.build_path (Path.DIR_SEPARATOR_S, project_path, filename);
                var file = File.new_for_path (path);
                if (file.query_exists())
                    action (path);
                else
                    stderr.printf (_("Warning: File not found: %s\n"), path);
            }
        } catch (GLib.Error e) {
            stderr.printf(_("Could not open file: %s\n"), e.message);
        }

    }

    public string build() {
        string ret;

        try {
            string pkg_list = "set(required_pkgs\n";
            foreach (string pkg in guanako_project.packages)
                pkg_list += pkg + "\n";
            pkg_list += ")";

            var file_stream = File.new_for_path (
                                    Path.build_path (Path.DIR_SEPARATOR_S,
                                                     project_path,
                                                     "cmake",
                                                     "project.cmake")).replace(
                                                            null,
                                                            false,
                                                            FileCreateFlags.REPLACE_DESTINATION);
            var data_stream = new DataOutputStream (file_stream);
            data_stream.put_string ("set(project_name " + project_name + ")\n");
            data_stream.put_string (@"set($(project_name)_VERSION $version_major.$version_minor.$version_patch)\n");
            data_stream.put_string (pkg_list);
            data_stream.close();
        } catch (GLib.IOError e) {
            stderr.printf(_("Could not read file: %s\n"), e.message);
        } catch (GLib.Error e) {
            stderr.printf(_("Could not open file: %s\n"), e.message);
        }

        try {
            GLib.Process.spawn_command_line_sync("sh -c 'cd " + project_path +
                                                    " && mkdir -p build && cd build && cmake .. && make'",
                                                 null,
                                                 out ret);
        } catch (GLib.SpawnError e) {
            stderr.printf(_("Could not execute build process: %s\n"), e.message);
        }
        return ret;
    }

    private void load_project_file() throws LoadingError {
        Xml.Doc* doc = Xml.Parser.parse_file (project_file);

        if (doc == null) {
            delete doc;
            throw new LoadingError.FILE_IS_GARBAGE (_("Cannot parse file."));
        }

        Xml.Node* root_node = doc->get_root_element();
        if (root_node == null) {
            delete doc;
            throw new LoadingError.FILE_IS_EMPTY (_("File does not contain enough information"));
        }

        var packages = new string[0];
        var source_dirs = new string[0];
        var source_files = new string[0];
        var buildsystem_dirs = new string[0];
        var buildsystem_files = new string[0];
        for (Xml.Node* i = root_node->children; i != null; i = i->next) {
            if (i->type != ElementType.ELEMENT_NODE)
                continue;
            switch (i->name) {
                case "name":
                    project_name = i->get_content();
                    break;
                case "packages":
                    for (Xml.Node* p = i->children; p != null; p = p->next)
                        if (p->name == "package")
                            packages += p->get_content();
                    break;
                case "version":
                    for (Xml.Node* p = i->children; p != null; p = p->next) {
                        if (p->name == "major")
                            version_major = int.parse (p->get_content());
                        else if (p->name == "minor")
                            version_minor = int.parse (p->get_content());
                        else if (p->name == "patch")
                            version_patch = int.parse (p->get_content());
                    }
                    break;
                case "source-directories":
                    for (Xml.Node* p = i-> children; p != null; p = p->next)
                        if (p->name == "directory")
                            source_dirs += p->get_content();
                    break;
                case "source-files":
                    for (Xml.Node* p = i-> children; p != null; p = p->next)
                        if (p->name == "file")
                            source_files += p->get_content();
                    break;
                case "buildsystem-directories":
                    for (Xml.Node* p = i-> children; p != null; p = p->next)
                        if (p->name == "directory")
                            buildsystem_dirs += p->get_content();
                    break;
                case "buildsystem-files":
                    for (Xml.Node* p = i-> children; p != null; p = p->next)
                        if (p->name == "file")
                            buildsystem_files += p->get_content();
                    break;
                default:
                    stderr.printf ("Warning: Unknown configuration file value: %s", i->name);
                    break;
            }
        }
        string[] missing_packages = guanako_project.add_packages (packages, false);
        project_source_dirs = source_dirs;
        project_source_files = source_files;
        project_buildsystem_dirs = buildsystem_dirs;
        project_buildsystem_files = buildsystem_files;

        if (missing_packages.length > 0)
            ui_missing_packages_dialog (missing_packages);

        delete doc;
    }

    public void save() {
        var writer = new TextWriter.filename (project_file);
        writer.set_indent (true);
        writer.set_indent_string ("\t");

        writer.start_element ("project");
        writer.write_element ("name", project_name);

        writer.start_element ("version");
        writer.write_element ("major", version_major.to_string());
        writer.write_element ("minor", version_minor.to_string());
        writer.write_element ("patch", version_patch.to_string());
        writer.end_element();

        writer.start_element ("packages");
        foreach (string pkg in guanako_project.packages)
            writer.write_element ("package", pkg);
        writer.end_element();

        writer.start_element ("source-directories");
        foreach (string directory in project_source_dirs)
            writer.write_element ("directory", directory);
        writer.end_element();

        writer.start_element ("source-files");
        foreach (string directory in project_source_files)
            writer.write_element ("file", directory);
        writer.end_element();

        writer.start_element ("buildsystem-directories");
        foreach (string directory in project_buildsystem_dirs)
            writer.write_element ("directory", directory);
        writer.end_element();

        writer.start_element ("buildsystem-files");
        foreach (string directory in project_buildsystem_files)
            writer.write_element ("file", directory);
        writer.end_element();

        writer.end_element();
    }

    public SourceView? open_new_buffer (string txt = "", string filename = "") {
#if DEBUG
        string dbgstr;
        if (filename == "")
            dbgstr = _("(new file)");
        else
            dbgstr = filename;
        stdout.printf (_("Load new buffer: %s\n"), dbgstr);
#endif
        SourceView? view = null;
        foreach (var viewelement in vieworder) {
            if (viewelement.filename == filename) {
                vieworder.remove (viewelement);
                vieworder.offer_head (viewelement);
                return null;
            }
        }

        view = new SourceView();
        view.show_line_numbers = true;
        view.insert_spaces_instead_of_tabs = true;
        view.override_font (FontDescription.from_string ("Monospace 10"));
        view.buffer.create_tag ("gray_bg", "background", "gray", null);
        view.auto_indent = true;
        view.indent_width = 4;

        view.buffer.text = txt;

        var bfr = (SourceBuffer) view.buffer;
        bfr.set_highlight_syntax (true);
        var langman = new SourceLanguageManager();
        SourceLanguage lang;
        if (filename == "")
            lang = langman.get_language ("vala");
        else if (Path.get_basename (filename) == "CMakeLists.txt")
            lang = langman.get_language ("cmake");
        else
            lang = langman.guess_language (filename, null);

        if (lang != null) {
            bfr.set_language (lang);

            if (bfr.language.id == "vala")
                try {
                    view.completion.add_provider (this.comp_provider);
                } catch (GLib.Error e) {
                    stderr.printf (_("Could not load completion: %s\n"), e.message);
                }
        }

        view.buffer.changed.connect (() => {
            if (!parsing) {
                parsing = true;
                try {
                    /* Get a copy of the buffer that is safe to work on
                     * Otherwise, the thread might crash accessing it
                     */
                    string buffer_content =  view.buffer.text;
                    new Thread<void*>.try (_("Buffer update"), () => {
                        report_wrapper.clear();
                        var source_file = project.guanako_project.get_source_file_by_name(Path.build_path (
                                                        Path.DIR_SEPARATOR_S, project.project_path,
                                                        window_main.current_srcfocus));
                        project.guanako_project.update_file (source_file, buffer_content);
                        Idle.add (() => {
                            wdg_report.update();
                            parsing = false;
                            if (loop_update.is_running())
                                loop_update.quit();
                            return false;
                        });
                        return null;
                    });
                } catch (GLib.Error e) {
                    stderr.printf (_("Could not create thread to update buffer completion: %s\n"), e.message);
                }
            }
        });

        var vmap = new ViewMap (view, filename);
        vieworder.offer_head (vmap);
#if DEBUG
        stdout.printf (_("Buffer loaded.\n"));
#endif
        return view;
    }

    /**
     * Show dialog if {@link Gtk.SourceView} wasn't saved yet.
     *
     * Return true to close buffer.
     */
    public bool close_buffer (SourceView view) {
        /*
         * TODO: Not Implemented.
         *       Check if view.buffer is dirty. If so -> dialog
         */
        return false;
    }

    /**
     * Hold filename -> view mappings for {@link vieworder}.
     */
    private class ViewMap {
        public ViewMap (SourceView view, string filename) {
            this.view = view;
            this.filename = filename;
        }

        public SourceView view;
        public string filename;
        /**
         * Use unique id to support multiple views for same file.
         */
        // private static int size = 0;
        // public int id = size++;
    }

    /**
     * Get {@link Gtk.TextBuffer} by file name.
     */
    public TextBuffer? get_buffer_by_file (string filename) {
        foreach (var map in vieworder) {
            if (map.filename == filename)
                return (TextBuffer) map.view.buffer;
        }
        return null;
    }

    /**
     * Provide delegate to perform action on opened views. See
     * {@link foreach_view}.
     */
    public delegate void ViewCallback (string filename, string? buffertext);
    /**
     * Perform {@link ViewCallback} action for each opened {@link SourceView}.
     */
    public void foreach_view (ViewCallback action) {
        foreach (var map in vieworder)
            action (map.filename, map.view.buffer.text);
    }
}

errordomain LoadingError {
    FILE_IS_EMPTY,
    FILE_IS_GARBAGE
}

// vim: set ai ts=4 sts=4 et sw=4
