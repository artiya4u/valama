/*
 * src/ui_reports.vala
 * Copyright (C) 2012, Linus Seelinger <S.Linus@gmx.de>
 *               2012, Dominique Lasserre <lasserre.d@gmail.com>
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

using GLib;
using Gtk;

class UiReport : UiElement {
    ReportWrapper report;
    TreeView tree_view;
    public Widget widget;

    public UiReport (ReportWrapper report) {
        this.report = report;

        element_name = "UiReport";

        tree_view = new TreeView();
        tree_view.insert_column_with_attributes (-1, "Location", new CellRendererText(), "text", 0, null);
        tree_view.insert_column_with_attributes (-1, "Error", new CellRendererText(), "text", 1, null);

        build();

        tree_view.row_activated.connect ((path) => {
            int index = path.get_indices()[0];
            if (report.errors_list.size > index)
                error_selected (report.errors_list[index]);
            else
                error_selected (report.warnings_list[index - report.errors_list.size]);
        });
        tree_view.can_focus = false;

        widget = tree_view;
    }

    public signal void error_selected (ReportWrapper.Error error);

    public override void build() {
#if DEBUG
        stderr.printf ("Run reports widget update!\n");
#endif
        var store = new ListStore (2, typeof (string), typeof (string));
        tree_view.set_model (store);

        foreach (ReportWrapper.Error err in report.errors_list) {
            TreeIter next;
            store.append (out next);
            store.set (next, 0,
#if VALA_LESS_0_18
                                err.source.first_line.to_string(),
#else
                                err.source.begin.line.to_string(),
#endif
                                                                   1, err.message, -1);
        }
        foreach (ReportWrapper.Error err in report.warnings_list) {
            TreeIter next;
            store.append (out next);
            store.set (next, 0,
#if VALA_LESS_0_18
                                err.source.first_line.to_string(),
#else
                                err.source.begin.line.to_string(),
#endif
                                                                   1, err.message, -1);
        }
#if DEBUG
        stdout.printf ("Errors: %d, Warnings: %d\n", report.get_errors(), report.get_warnings());
#endif
#if DEBUG
        stderr.printf ("Report widget update finished!\n");
#endif
    }
}

public class ReportWrapper : Vala.Report {
    public Vala.List<Error?> errors_list = new Vala.ArrayList<Error?>();
    public Vala.List<Error?> warnings_list = new Vala.ArrayList<Error?>();
    bool general_error = false;

    public struct Error {
        public Vala.SourceReference source;
        public string message;
    }

    public void clear() {
        errors_list = new Vala.ArrayList<Error?>();
        warnings_list = new Vala.ArrayList<Error?>();
    }

    public override void warn (Vala.SourceReference? source, string message) {
#if DEBUG
        stdout.printf ("Warning found: %s: %d(%d)-%d(%d): %s\n",
                                               source.file.filename,
#if VALA_LESS_0_18
                                               source.first_line.line,
                                               source.last_line.column,
                                               source.last_line.line,
                                               source.last_line.column,
#else
                                               source.begin.line,
                                               source.end.column,
                                               source.end.line,
                                               source.end.column,
#endif
                                               message);
#endif
        warnings ++;

        if (source == null)
            return;
        //lock (errors_list) {
        warnings_list.add(Error() {source = source, message = message});
        //}
     }

     public override void err (Vala.SourceReference? source, string message) {
#if DEBUG
        stdout.printf ("Error found: %s: %d(%d)-%d(%d): %s\n",
                                               source.file.filename,
#if VALA_LESS_0_18
                                               source.first_line.line,
                                               source.first_line.column,
                                               source.last_line.line,
                                               source.last_line.column,
#else
                                               source.begin.line,
                                               source.begin.column,
                                               source.end.line,
                                               source.end.column,
#endif
                                               message);
#endif
         errors ++;

         if (source == null) {
             general_error = true;
             return;
         }
         //lock (errors_list) {
         errors_list.add (Error() {source = source, message = message});
         //}
    }
}

// vim: set ai ts=4 sts=4 et sw=4
