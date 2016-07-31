#!/usr/bin/env ruby

require 'nokogiri'
require 'open-uri'

DOC_URL = "https://mpv.io/manual/master/"

class String
  def to_camel
    self.strip.gsub(/(-|\/|\s)(.)/) {|e| $2.upcase}
  end
end

doc = Nokogiri::HTML open(DOC_URL)

# property

property_list = doc.css '#property-list .docutils > dt > tt'

File.open(File.join(__dir__, 'MPVProperty.swift'), 'w') do |file|
  file.write "import Foundation\n\n"
  file.write "struct MPVProperty {\n"
  property_list.each do |property|
    name = property.content
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

command_list = doc.css '#list-of-input-commands > .docutils > dt > tt'

File.open(File.join(__dir__, 'MPVCommand.swift'), 'w') do |file|
  file.write "import Foundation\n\n"
  file.write "struct MPVCommand {\n"
  command_list.each do |command|
    format = command.content
    name = format.split(' ')[0]
    file.write "  /** #{format} */\n"
    file.write "  static let #{name.to_camel} = \"#{name}\"\n"
  end
  file.write "}\n"
end
