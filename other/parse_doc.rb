#!/usr/bin/env ruby

require 'nokogiri'
require 'open-uri'

DOC_URL = "https://mpv.io/manual/stable/"

class String
  def to_camel
    self.strip.gsub(/(-|\/|\s)(.)/) {|e| $2.upcase}
  end
end

doc = Nokogiri::HTML open(DOC_URL)

# property

nodes = doc.css '#property-list > .docutils > dt, #property-list > .docutils > dd'
$prop_set = Hash.new(0)

def write_prop(file, node)
  name = node.content
  camel_name = name.to_camel
  if (count = $prop_set[camel_name]) > 0
    name = "#{camel_name}#{count}"
  end
  $prop_set[camel_name] += 1

  if name.include? '/'
    if name.include? 'N'
      func_name = name.to_camel
      return_str = name.gsub('N', '\(n)')
      file.write "  /** #{name} */\n"
      file.write "  static func #{func_name}(_ n: Int) -> String {\n"
      file.write "    return \"#{return_str}\"\n"
      file.write "  }\n"
    elsif name.include? '<name>'
      func_name = name.gsub('/<name>', '').to_camel
      return_str = name.gsub('<name>', '\(name)')
      file.write "  /** #{name} */\n"
      file.write "  static func #{func_name}(_ name: String) -> String {\n"
      file.write "    return \"#{return_str}\"\n"
      file.write "  }\n"
    elsif not name.match(/<.+?>/)
      file.write "  /** #{name} */\n"
      file.write "  static let #{name.to_camel} = \"#{name}\"\n"
    end
  else
    file.write "  /** #{name} */\n"
    file.write "  static let #{name.to_camel} = \"#{name}\"\n"
  end
end

File.open(File.join(__dir__, 'MPVProperty.swift'), 'w') do |file|
  file.write "import Foundation\n\n"
  file.write "struct MPVProperty {\n"
  nodes.each do |node|
    if node.name == 'dt'
      props = node.css('tt')
      props.each do |prop|
        write_prop(file, prop)
      end
    else
      sub_props = node.css '.docutils > dt > tt'
      sub_props.each do |prop|
        write_prop(file, prop) if prop.content.include? '/'
      end
    end
  end
  file.write "}\n"
end

# option

option_sections = doc.css '#options > .section'

exist_op = []

File.open(File.join(__dir__, 'MPVOption.swift'), 'w') do |file|
  file.write "import Foundation\n\n"
  file.write "struct MPVOption {\n"

  option_sections.each do |section|
    section_title = section.at_css 'h2'
    section_title_camel = section_title.content.to_camel
    if section_title_camel == 'TV' then next end  # jump tv 
    file.write "  struct #{section_title_camel} {\n"
    option_list = section.xpath './dl/dt/tt'
    option_list.each do |option|
      # puts option
      op_format = option.content
      op_format.gsub(/<(.+?)>/) {|m| $0.gsub(',', '$')}  # remove ',' temporarily
      op_format.split(',').each do |f|
        f.gsub('$', ',')  # add back ','
        match = f.match(/--(.+?)(=|\Z)/)
        if match.nil? then next end
        op_name = match[1]
        if exist_op.include?(op_name) or op_name.include?('...') then next end
        file.write "    /** #{f} */\n"
        file.write "    static let #{op_name.to_camel} = \"#{op_name}\"\n"
        exist_op << op_name
      end
    end
    file.write "  }\n\n"
  end

  file.write "}\n"
end

# command

command_list = doc.css '#list-of-input-commands > .docutils > dt > tt, #input-commands-that-are-possibly-subject-to-change > .docutils > dt > tt'

File.open(File.join(__dir__, 'MPVCommand.swift'), 'w') do |file|
  file.write "import Foundation\n\n"
  file.write "struct MPVCommand: RawRepresentable {\n\n"
  file.write "  typealias RawValue = String\n\n"
  file.write "  var rawValue: RawValue\n\n"
  file.write "  init(_ string: String) { self.rawValue = string }\n\n"
  file.write "  init?(rawValue: RawValue) { self.rawValue = rawValue }\n\n"
  command_list.each do |command|
    format = command.content
    name = format.split(' ')[0]
    file.write "  /** #{format} */\n"
    file.write "  static let #{name.to_camel} = MPVCommand(\"#{name}\")\n"
  end
  file.write "}\n"
end
