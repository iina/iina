#!/usr/bin/env ruby

require 'nokogiri'
require 'open-uri'

doc = Nokogiri::HTML open("https://mpv.io/manual/master/")

property_list = doc.css '#property-list .docutils > dt'

File.open(File.join(__dir__, 'MPVProperty.swift'), 'w') do |file|
  file.write "import Foundation\n\n"
  file.write "struct MPVProperty {\n"
  property_list.each do |property|
    name = property.at_css('tt').content
    if name.include? '/' then next end
    name.split(',').each do |n|
      camel = n.gsub(/-(.)/) {|e| $1.upcase}
      file.write "  static let #{camel} = \"#{n}\"\n"
    end
  end
  file.write "}\n"
end