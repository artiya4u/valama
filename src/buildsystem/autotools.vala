public class BuilderAutotools : BuildSystem
{
	string configure_ac;
	string makefile_am;
	bool autoreconfigured;
	
	public BuilderAutotools (bool make_lib = false)
	{
		Object(library: make_lib);
	}
	
	public override string get_executable() {
		return project.project_name.down();
	}

	public override inline string get_name() {
		return "Autotools";
	}

	public override inline string get_name_id() {
		return "autotools";
	}
	
	public override bool check_buildsystem_file (string filename) {
		return filename == "configure.ac";
	}
	
	public override bool preparate() throws BuildError.INITIALIZATION_FAILED {
        if (project == null)
            throw new BuildError.INITIALIZATION_FAILED (_("Valama project not initialized."));
        buildpath = project.project_path;
        configure_ac = Path.build_path (Path.DIR_SEPARATOR_S,
                                       project.project_path,
                                       "configure.ac");
        makefile_am = Path.build_path (Path.DIR_SEPARATOR_S,
                                       project.project_path,
                                       "Makefile.am");
        init_dir (buildpath);
        init_dir (Path.build_path (Path.DIR_SEPARATOR_S, buildpath, "m4"));
        return true;
	}
	
	bool autoreconf (out int? exit_status = null) throws BuildError.INITIALIZATION_FAILED,
                                            BuildError.CONFIGURATION_FAILED {
        exit_status = null;
        if (!initialized && !initialize (out exit_status))
            return false;
		
        exit_status = null;
        autoreconfigured = false;
        configure_started();

        var cmdline = new string[] {"autoreconf", "-f", "-i"};
        Pid? pid;
        if (!call_cmd (cmdline, out pid)) {
            configure_finished();
            throw new BuildError.CONFIGURATION_FAILED (_("autoreconf command failed"));
        }
        
        int? exit = null;
        ChildWatch.add (pid, (intpid, status) => {
            exit = get_exit (status);
            Process.close_pid (intpid);
            builder_loop.quit();
        });
        
        builder_loop.run();
        exit_status = exit;
        autoreconfigured = true;
        configure_finished();
        return exit_status == 0;
    }
	
	public override bool configure (out int? exit_status = null) throws BuildError.INITIALIZATION_FAILED,
                                            BuildError.CONFIGURATION_FAILED {
        exit_status = null;
        if (!autoreconfigured && !autoreconf (out exit_status))
            return false;

        exit_status = null;
        configured = false;
        configure_started();

        var cmdline = new string[] {Path.build_path (Path.DIR_SEPARATOR_S,
                                       project.project_path,
                                       "configure")};
        Pid? pid;
        if (!call_cmd (cmdline, out pid)) {
            configure_finished();
            throw new BuildError.CONFIGURATION_FAILED (_("configure command failed"));
        }

        int? exit = null;
        ChildWatch.add (pid, (intpid, status) => {
            exit = get_exit (status);
            Process.close_pid (intpid);
            builder_loop.quit();
        });

        builder_loop.run();
        exit_status = exit;
        configured = true;
        configure_finished();
        return exit_status == 0;
    }
    
    public override bool initialize (out int? exit_status = null)
                                        throws BuildError.INITIALIZATION_FAILED {
        exit_status = null;
        initialized = false;
        if(!preparate())
            return false;
        initialize_started();

        try {
            var file_stream = File.new_for_path (configure_ac).replace (
                                                    null,
                                                    false,
                                                    FileCreateFlags.REPLACE_DESTINATION);
            var data_stream = new DataOutputStream (file_stream);
			var str_name = project.project_name.replace("-","_");
            /*
             * Don't translate this part to make collaboration with VCS and
             * multiple locales easier.
             */
            data_stream.put_string ("dnl This file was auto generated by Valama %s. Do not modify it.\n".printf (Config.PACKAGE_VERSION));
            //TODO: Check if file needs changes and set date accordingly.
            // var time = new DateTime.now_local();
            // data_stream.put_string ("dnl Last change: %s\n".printf (time.format ("%F %T %z")));
            data_stream.put_string (@"AC_INIT([$str_name], [$(project.version_major).$(project.version_minor)])\n");
            data_stream.put_string ("AC_CONFIG_HEADERS(config.h)\n");
            data_stream.put_string ("AC_CONFIG_MACRO_DIR([m4])\n");
            data_stream.put_string ("AM_INIT_AUTOMAKE([check-news dist-bzip2 subdir-objects])\n");
            data_stream.put_string ("m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES([yes])])\n");
            data_stream.put_string ("\n");
            data_stream.put_string ("AM_PROG_AR\n");
            data_stream.put_string ("LT_INIT\n");
            data_stream.put_string ("AC_PROG_CC\n");
            data_stream.put_string ("AM_PROG_VALAC\n");
            data_stream.put_string ("\n");
	        data_stream.put_string ("PKG_CHECK_MODULES("+str_name.up()+", [");
	        foreach (var pkgmap in get_pkgmaps().values) {
				var pkg = "";
                if (pkgmap.choice_pkg != null && !pkgmap.check)
				    pkg = @"$(pkgmap as PackageInfo)".split (" ")[0];
                else
				    pkg = @"$(pkgmap)".split (" ")[0];
				if (pkg != "posix")
			        data_stream.put_string (pkg + " ");
            }
	        data_stream.put_string ("])\n");
	        data_stream.put_string (@"AC_SUBST($(str_name.up())_CFLAGS)\n");
	        data_stream.put_string (@"AC_SUBST($(str_name.up())_LIBS)\n");
            data_stream.put_string ("\n");
            data_stream.put_string ("AC_CONFIG_FILES([Makefile])\n");
            data_stream.put_string ("AC_OUTPUT\n");
			
            data_stream.close();
            
            file_stream = File.new_for_path (makefile_am).replace (
                                                    null,
                                                    false,
                                                    FileCreateFlags.REPLACE_DESTINATION);
                                                    
			data_stream = new DataOutputStream (file_stream);
			data_stream.put_string ("AM_CFLAGS = $("+str_name.up()+"_CFLAGS)\n\n");
			string lower_libname = null;
			if (library)
			{
				string libname = project.project_name.has_prefix ("lib") ? project.project_name : "lib"+project.project_name;
				libname += ".la";
				lower_libname = libname.replace ("-","_").replace (".","_");
				data_stream.put_string ("lib_LTLIBRARIES = "+libname+"\n\n");
				data_stream.put_string (lower_libname+"_LIBADD = $("+str_name.up()+"_LIBS)\n\n");
				data_stream.put_string (str_name.down()+"includedir = $(includedir)\n");
				data_stream.put_string (str_name.down()+@"include_HEADERS = $(str_name.down()).h\n\n");
				data_stream.put_string ("pkgconfigdir = $(libdir)/pkgconfig\n");
				data_stream.put_string (@"pkgconfig_DATA = $(str_name.down()).pc\n\n");
				data_stream.put_string ("vapidir = $(datadir)/vala/vapi\n");
				data_stream.put_string (@"dist_vapi_DATA = $(str_name.down()).vapi $(str_name.down()).deps\n\n");
			}
			else {
			    data_stream.put_string ("bin_PROGRAMS = "+project.project_name+"\n\n");
			    data_stream.put_string (str_name+"_LDADD = $("+str_name.up()+"_LIBS)\n\n");
			}
			var str_files = new StringBuilder ((library ? lower_libname : str_name.down())+"_SOURCES = ");
			foreach (var filepath in project.files) {
				var fname = project.get_relative_path (filepath);
				str_files.append (@"$fname ");
			}
			str_files.append ("\n\n");
			data_stream.put_string (str_files.str);
			var str_pkgs = new StringBuilder ((library ? lower_libname : str_name.down())+"_VALAFLAGS = ");
			foreach (var pkgmap in get_pkgmaps().values) {
				var pkg = "";
                if (pkgmap.choice_pkg != null && !pkgmap.check)
				    pkg = @"$(pkgmap as PackageInfo)".split (" ")[0];
                else
				    pkg = @"$(pkgmap)".split (" ")[0];
			        str_pkgs.append ("--pkg " + pkg + " ");
            }
			if (library)
			{
				str_pkgs.append (" --vapi %s.vapi -H %s.h --library %s".printf(str_name.down(),str_name.down(),str_name.down()));
			}
			str_pkgs.append ("\n\n");
			data_stream.put_string (str_pkgs.str);
			data_stream.put_string ("CLEANFILES = *.c *.o "+str_name.down()+"\n");
			data_stream.close();
			
			if (library)
			{
				var str_deps = Path.build_path (Path.DIR_SEPARATOR_S,
                                       project.project_path,
                                       str_name.down()+".deps");
			    file_stream = File.new_for_path (str_deps).create (FileCreateFlags.REPLACE_DESTINATION);
			    data_stream = new DataOutputStream (file_stream);
			    foreach (var pkgmap in get_pkgmaps().values) {
				    if (pkgmap.choice_pkg != null && !pkgmap.check)
					    data_stream.put_string (@"$(pkgmap as PackageInfo)\n");
					else
					    data_stream.put_string (@"$pkgmap\n");
				}
			    data_stream.close();
			    
				var str_pc = Path.build_path (Path.DIR_SEPARATOR_S,
                                       project.project_path,
                                       str_name.down()+".pc");
			    file_stream = File.new_for_path (str_pc).create (FileCreateFlags.REPLACE_DESTINATION);
			    data_stream = new DataOutputStream (file_stream);
			    var short_name = project.project_name.has_prefix ("lib") ? 
					project.project_name.substring (3) : 
					project.project_name;
				var req = "";
				foreach (var pkgmap in get_pkgmaps().values) {
				    if (pkgmap.choice_pkg != null && !pkgmap.check)
					    req += @"$(pkgmap as PackageInfo) ";
					else
					    req += @"$pkgmap ";
				}
			    data_stream.put_string ("""prefix=@prefix@
exec_prefix=@exec_prefix@
libdir=@libdir@
datarootdir=@datarootdir@
datadir=@datadir@
includedir=@includedir@/%s

Name: Mee
Description: .pc file created by Valama.
Version: @VERSION@
Requires: %s
Libs: -L${libdir} -l%s
Cflags: -I${includedir}""".printf (project.project_name, req, short_name));
			    data_stream.close();
			}
			
        } catch (GLib.IOError e) {
            throw new BuildError.INITIALIZATION_FAILED (_("Could not read file: %s\n"), e.message);
        } catch (GLib.Error e) {
            throw new BuildError.INITIALIZATION_FAILED (_("Could not open file: %s\n"), e.message);
        }

        exit_status = 0;
        initialized = true;
        initialize_finished();
        return true;
    }
    
    public override bool build (out int? exit_status = null) throws BuildError.INITIALIZATION_FAILED,
                                        BuildError.CONFIGURATION_FAILED,
                                        BuildError.BUILD_FAILED {
        exit_status = null;
        if (!configured && !configure (out exit_status))
            return false;

        exit_status = null;
        built = false;
        build_started();
        var cmdline = new string[] {"make"};

        Pid? pid;
        int? pstdout, pstderr;
        if (!call_cmd (cmdline, out pid, true, out pstdout, out pstderr)) {
            build_finished();
            throw new BuildError.CONFIGURATION_FAILED (_("build command failed"));
        }

        var chn = new IOChannel.unix_new (pstdout);
        chn.set_buffer_size (1);
        chn.add_watch (IOCondition.IN | IOCondition.HUP, (source, condition) => {
            bool ret;
            var output = channel_output_read_line (source, condition, out ret);
            Regex r = /^\[(?P<percent>.*)\%\].*$/;
            MatchInfo info;
            if (r.match (output, 0, out info)) {
                var percent_string = info.fetch_named ("percent");
                build_progress (int.parse (percent_string));
            }
            build_output (output);
            return ret;
        });

        var chnerr = new IOChannel.unix_new (pstderr);
        chnerr.set_buffer_size (1);
        chnerr.add_watch (IOCondition.IN | IOCondition.HUP, (source, condition) => {
            bool ret;
            build_output (channel_output_read_line (source, condition, out ret));
            return ret;
        });

        int? exit = null;
        ChildWatch.add (pid, (intpid, status) => {
            exit = get_exit (status);
            Process.close_pid (intpid);
            builder_loop.quit();
        });

        builder_loop.run();
        exit_status = exit;
        built = true;
        build_finished();
        return exit_status == 0;
    }
    
    public override bool check_existance() {
        var f = File.new_for_path (buildpath);
        return f.query_exists();
    }
    
    public override bool clean (out int? exit_status = null)
                                        throws BuildError.CLEAN_FAILED {
        exit_status = null;
        // cleaned = false;
        clean_started();

        if (!check_existance()) {
            build_output (_("No data to clean.\n"));
            clean_finished();
            return true;
        }

        var cmdline = new string[] {"make", "clean"};

        Pid? pid;
        if (!call_cmd (cmdline, out pid)) {
            clean_finished();
            throw new BuildError.CLEAN_FAILED (_("clean command failed"));
        }

        int? exit = null;
        ChildWatch.add (pid, (intpid, status) => {
            exit = get_exit (status);
            Process.close_pid (intpid);
            builder_loop.quit();
        });

        builder_loop.run();
        exit_status = exit;
        // cleaned = true;
        clean_finished();
        return exit_status == 0;
    }
    
    public override bool distclean (out int? exit_status = null)
                                            throws BuildError.CLEAN_FAILED {
        exit_status = null;
        // distcleaned = false;
        distclean_started();
        project.enable_defines_all();
		exit_status = 0;
        return exit_status == 0;
    }
}
