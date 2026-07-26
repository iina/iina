#!/usr/bin/env ruby

# Usage:
# other/l10n_xib_to_strings.rb iina/Base.lproj/PrefGeneralViewController.xib

require 'nokogiri'

class String
  def to_camel
    self.strip.gsub(/(-|\/|\s)(.)/) {|e| $2.upcase}
  end

  def sub_quote
    self.gsub(/"/, '\"')
  end
end

xml_file = ARGV[0]
base_name = File.basename(xml_file)
page_name = base_name.gsub(/^Pref/, '').gsub(/ViewController.xib$/, '')

# Read strings in zh-Hans.lproj
en_filename = xml_file.gsub(/\.xib$/, '.strings').gsub(/Base.lproj/, 'en.lproj')
en_file = File.open(en_filename, 'r')
en_dict = {}
en_file.each_line do |line|
  if line =~ /^"(.+)\.title" = "(.+)";$/
    en_dict[$1] = $2.gsub(/\\\"/, '"')
  end
end

# Read xib
doc = File.open(xml_file) { |f| Nokogiri::XML(f) }

# Find the <userDefaultsController> node
ud_node = doc.at_xpath('//userDefaultsController')

if ud_node
  ud_id = ud_node['id']
  # Find all nodes with a <connections> child containing one or more <binding> tags
  nodes = doc.xpath("//*[connections/binding[@destination='#{ud_id}']]")
else
  nodes = []
end

res_dict = {}

# Process each matching node
nodes.each do |node|
  pref_key = nil

  node.xpath('./connections/binding').each do |binding|
    next unless binding['destination'] == ud_id

    key_path = binding['keyPath']
    raise 'Could not find keyPath' unless key_path

    pref_key = key_path.split('.').last

    case binding['name']
    when 'selectedTag'
    when 'enabled'
    when 'value'
    end

    raise 'Could not find pref key' unless pref_key
    processed = false

    # Determine the control type

    if binding['name'] == 'selectedTag'
      if node.name == 'popUpButton'
        res_dict[pref_key] = {}
        prev_node = node.previous_element
        if prev_node and prev_node.name == 'textField'
          res_dict[pref_key][:label] = prev_node.at_xpath('./textFieldCell')['title']
        end
        res_dict[pref_key][:type] = :popup
        items = node.xpath('./popUpButtonCell/menu/items/menuItem')
        res_dict[pref_key][:items] = items.map { |item| [(item['tag'] or "0"), item['title'], item['id']] }
        processed = true
      end
    elsif binding['name'] == 'enabled'
      processed = true
    elsif binding['name'] == 'value'
      if node.name == 'button'
        button_cell = node.at_xpath('./buttonCell')
        if button_cell['type'] == 'check'
          res_dict[pref_key] = {}
          res_dict[pref_key][:type] = :checkbox
          res_dict[pref_key][:label] = button_cell['title']
          res_dict[pref_key][:id] = button_cell['id']
          processed = true
        end
      end
    end

    if processed and binding['name'] != 'enabled'
      possible_desc = binding.parent.parent.next_element
      if possible_desc&.name == 'textField'
        res_dict[pref_key][:desc] = possible_desc.at_xpath('./textFieldCell')['title']
        res_dict[pref_key][:desc_id] = possible_desc.at_xpath('./textFieldCell')['id']
      end
    end

    unless processed
      puts "Unknown control type #{node.name} (#{binding['name']}) for keyPath #{key_path}"
      next
    end
  end
end

string_file = File.open("Settings#{page_name}Localizable.strings", 'w')

swift_file = File.open("SettingsLocalizationKeys#{page_name}.swift", 'w')
swift_file.puts "extension SettingsLocalization.Key {"

res_dict.each do |key, value|
  en_dict.delete(value[:id])
  string_file.puts %Q{/* id="#{value[:id]}" */}
  string_file.puts %Q{"#{key}.label" = "#{value[:label]&.sub_quote}";}
  swift_file.puts %Q{  static let #{key}Label = SettingsLocalization.Key("#{key}.label")}

  if value[:desc]
    en_dict.delete(value[:desc_id])
    string_file.puts %Q{/* id="#{value[:desc_id]}" */}
    string_file.puts %Q{"#{key}.desc" = "#{value[:desc]&.sub_quote}";}
    swift_file.puts %Q{  static let #{key}Desc = SettingsLocalization.Key("#{key}.desc")}
  end

  if value[:type] == :popup
    value[:items].each do |item|
      en_dict.delete(item[2])
      string_file.puts %Q{/* id="#{item[2]}" */}
      string_file.puts %Q{"#{key}.items.#{item[0]}" = "#{item[1]&.sub_quote}";}
      swift_file.puts %Q{  static let #{key}Item#{item[0].to_camel} = SettingsLocalization.Key("#{key}.items.#{item[0]}")}
    end
  end
end

new_key_set = Set.new

en_dict.each do |key, value|
  newKey = value.gsub(/[^A-Za-z ]/, '').split(' ').first(5).join('-').to_camel
  next if new_key_set.include?(newKey)

  new_key_set.add(newKey)
  string_file.puts %Q{/* key="#{key}" */}
  string_file.puts %Q{"$#{newKey}" = "#{value.sub_quote}";}
  swift_file.puts %Q{  static let text_#{newKey} = SettingsLocalization.Key("$#{newKey}")}
end

string_file.close

swift_file.puts "}"
swift_file.close
