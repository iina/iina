#!/usr/bin/env ruby

require 'open3'

LIB_NAME = "libmpv.1.dylib"

proj_path = File.expand_path(File.join(File.dirname(__FILE__), '../'))
lib_folder = File.join(proj_path, "libmpv/lib/")
lib_path = File.join(lib_folder, LIB_NAME)

libs = [lib_path]
fix_count = 0

while not libs.empty?

  curr_lib = libs.pop

  puts "=== Fix dependencies for #{curr_lib} ===\n"

  stdout,stderr,status = Open3.capture3("otool -L #{curr_lib}")

  if status.success?
    deps = stdout.split("\n\t").drop(1).map {|s| s.gsub(/ \(.+?\)/, "").strip}
    changes = []
    deps.each do |d|
      basename = File.basename(d)
      if basename == File.basename(curr_lib) then next end
      if d.start_with?("/usr/local/opt/", "/usr/local/Cellar/")
        basename = File.basename(d)
        fix_count += 1
        changes.push "sudo install_name_tool -change '#{d}' '@rpath/#{basename}' '#{curr_lib}'"
        cpout, cperr, cpstatus = Open3.capture3("sudo cp '#{d}' #{lib_folder}")
        if cpstatus.success?
          puts "\tcopied #{d} to #{lib_folder}"
          dest = File.join(lib_folder, basename)
          libs.push(dest)
          Open3.capture3("sudo install_name_tool -change '#{d}' '@rpath/#{basename}' '#{curr_lib}'")
        else
          abort(cperr)
        end
      end
    end
    # puts changes
    # puts copies
  else
    puts 'Error!'
    puts stderr
  end

end

puts "Totol #{fix_count}"