/*
 * src/ui_create_file_dialog.vala
 * Copyright (C) 2012, Dominique Lasserre <lasserre.d@gmail.com>
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

using Gtk;
using GLib;
using Vala;

/*
 * Create new file and add it to project. If file already exists, open it.
 */
public SourceFile? ui_create_file_dialog (ValamaProject project) {
    var dlg = new Dialog.with_buttons (_("Choose filename"),
                                       window_main,
                                       DialogFlags.MODAL,
                                       Stock.CANCEL,
                                       ResponseType.CANCEL,
                                       Stock.OPEN,
                                       ResponseType.ACCEPT,
                                       null);

    dlg.set_size_request (420, 100);
    dlg.resizable = false;

    var box_main = new Box (Orientation.VERTICAL, 0);
    var frame_filename = new Frame (_("Add new file to project"));
    var box_filename = new Box (Orientation.VERTICAL, 0);
    frame_filename.add (box_filename);

    var ent_filename_err = new Label ("");
    ent_filename_err.sensitive = false;

    Regex valid_chars = /^[a-z0-9.:_-]+$/i;  // keep "-" at the end!
    var ent_filename = new Entry.with_inputcheck (ent_filename_err, valid_chars);
    ent_filename.set_placeholder_text(_("filename"));  // this is i.g. not visible

    box_filename.pack_start (ent_filename, false, false);
    box_filename.pack_start (ent_filename_err, false, false);
    box_main.pack_start (frame_filename, true, true);
    box_main.show_all();
    dlg.get_content_area().pack_start (box_main);

    SourceFile source_file = null;
    dlg.response.connect ((response_id) => {
        if (response_id == ResponseType.ACCEPT) {
            if (ent_filename.text == "") {
                ent_filename.set_label_timer (_("Don't let this field empty. Name a file."), 10);
                return;
            }
            string filename = join_paths ({project.project_path, "src", ent_filename.text});
            if (!filename.has_suffix (".vala"))
                filename += ".vala";
            var f = File.new_for_path (filename);
            if (!f.query_exists()) {
                try {
                        f.create (FileCreateFlags.NONE).close();
                } catch (GLib.IOError e) {
                    stderr.printf (_("Could not write to new file: %s"), e.message);
                } catch (GLib.Error e) {
                    stderr.printf (_("Could not create new file: %s"), e.message);
                }
            }
            source_file = project.guanako_project.add_source_file_by_name(filename);
        }
        dlg.destroy();
    });
    dlg.run();

    return source_file;
}

// vim: set ai ts=4 sts=4 et sw=4