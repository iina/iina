#!/usr/bin/env ruby

require "fileutils"
require "open3"
require "shellwords"

include FileUtils::Verbose

def safe_system(*args)
  puts args.shelljoin
  system(*args) || abort("Fail to run the last command!")
end

class DylibFile
  OTOOL_RX = /\t(.*) \(compatibility version (?:\d+\.)*\d+, current version (?:\d+\.)*\d+\)/

  attr_reader :path, :id, :deps

  def initialize(path)
    @path = path
    parse_otool_L_output!
  end

  def parse_otool_L_output!
    stdout, stderr, status = Open3.capture3("otool -L #{path}")
    abort(stderr) unless status.success?
    libs = stdout.split("\n")
    libs.shift # first line is the filename
    @id = libs.shift[OTOOL_RX, 1]
    @deps = libs.map { |lib| lib[OTOOL_RX, 1] }.compact
  end

  def ensure_writeable
    saved_perms = nil
    unless File.writable_real?(path)
      saved_perms = File.stat(path).mode
      FileUtils.chmod 0644, path
    end
    yield
  ensure
    FileUtils.chmod saved_perms, path if saved_perms
  end

  def change_id!(new_id)
    ensure_writeable do
      safe_system "install_name_tool", "-id", new_id, path
    end
  end

  def change_install_name!(old_name, new_name)
    ensure_writeable do
      safe_system "install_name_tool", "-change", old_name, new_name, path
    end
  end
end

mpv_files = Dir["#{`brew --prefix mpv`.chomp}/lib/*.dylib"]
proj_path = File.expand_path(File.join(File.dirname(__FILE__), '../'))
lib_folder = File.join(proj_path, "libmpv/lib/")

libs = []

rm_rf lib_folder
mkdir lib_folder

mpv_files.each do |file|
  dest = File.join(lib_folder, File.basename(file))
  puts "cp -p #{file} #{dest}"
  copy_entry file, dest, preserve: true
  libs << dest unless File.symlink?(dest)
end

fix_count = 0

libs.each do |file|
  fix_count += 1
  dylib = DylibFile.new file
  new_id = "@executable_path/../Frameworks/#{File.basename(dylib.id)}"
  dylib.change_id!(new_id)
end

while !libs.empty?
  file = libs.pop
  puts "=== Fix dependencies for #{file} ==="
  dylib = DylibFile.new file
  dylib.deps.each do |dep|
    if dep.start_with?("/usr/local")
      fix_count += 1
      basename = File.basename(dep)
      new_name = "@rpath/#{basename}"
      dylib.change_install_name!(dep, new_name)
      dest = File.join(lib_folder, basename)
      unless File.exists?(dest)
        cp dep, lib_folder, preserve: true
        libs << dest
      end
    end
  end
end

puts "Total #{fix_count}"
