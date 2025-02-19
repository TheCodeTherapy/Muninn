/*
┌─────────────────────────────────────────────────────────────────────────────┐
│ copy of the console logger in `core:log` using emscripten's `puts` proc to  │
│ write into he console of the web browser.                                   │
└─────────────────────────────────────────────────────────────────────────────┘
*/

package main_web

import "core:c"
import "core:fmt"
import "core:log"
import "core:strings"

Web_Logger_Opts :: log.Options{.Level, .Short_File_Path, .Line}

create_web_logger :: proc(lowest := log.Level.Debug, opt := Web_Logger_Opts) -> log.Logger {
	return log.Logger {
		data = nil,
		procedure = web_logger_proc,
		lowest_level = lowest,
		options = opt,
	}
}

/*
┌─────────────────────────────────────────────────────────────────────────────┐
│ binding to `puts` which will be linked in as part of the emscripten runtime.│
└─────────────────────────────────────────────────────────────────────────────┘
*/
@(default_calling_convention = "c")
foreign _ {
	puts :: proc(buffer: cstring) -> c.int ---
}

@(private = "file")
web_logger_proc :: proc(
	logger_data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, Web_Logger_Level_Headers[level])
	do_location_header(options, &b, location)
	fmt.sbprint(&b, text)
	puts(strings.to_cstring(&b))
}

@(private = "file")
Web_Logger_Level_Headers := [?]string {
	0 ..< 10 = "[DEBUG] --- ",
	10 ..< 20 = "[INFO ] --- ",
	20 ..< 30 = "[WARN ] --- ",
	30 ..< 40 = "[ERROR] --- ",
	40 ..< 50 = "[FATAL] --- ",
}

@(private = "file")
do_location_header :: proc(
	opts: log.Options,
	buf: ^strings.Builder,
	location := #caller_location,
) {
	if log.Location_Header_Opts & opts == nil {
		return
	}
	fmt.sbprint(buf, "[")
	file := location.file_path
	if .Short_File_Path in opts {
		last := 0
		for r, i in location.file_path {
			if r == '/' {
				last = i + 1
			}
		}
		file = location.file_path[last:]
	}

	if log.Location_File_Opts & opts != nil {
		fmt.sbprint(buf, file)
	}
	if .Line in opts {
		if log.Location_File_Opts & opts != nil {
			fmt.sbprint(buf, ":")
		}
		fmt.sbprint(buf, location.line)
	}

	if .Procedure in opts {
		if (log.Location_File_Opts | {.Line}) & opts != nil {
			fmt.sbprint(buf, ":")
		}
		fmt.sbprintf(buf, "%s()", location.procedure)
	}

	fmt.sbprint(buf, "] ")
}
