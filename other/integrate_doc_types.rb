#!/usr/bin/env ruby

require "plist"
require "fileutils"
require "shellwords"
require "colorize"

INFO_PLIST_PATH = 'iina/info.plist'
ASSETS_PATH = 'iina/Assets.xcassets/'
ICON_PATH = 'psd/Doc/'

FT_DATA = [
  { ext: %w(mkv mka mk3d mks), icon: 'mkv', name: 'Matroska media' },
  { ext: %w(rm rmvb ra), icon: 'rm', name: 'Real Media file' },
  { ext: %w(asf), icon: 'asf', name: 'Advanced Systems Format (ASF) media' },
  { ext: %w(aac), icon: 'aac', name: 'Advanced Audio Coding (AAC) media' },
  { ext: %w(flv f4v f4p f4a f4b), icon: 'flv', name: 'Flash Video file' },
  { ext: %w(webm), icon: 'webm', name: 'WebM media' },
  { ext: %w(3gp 3g2), icon: '3gp', name: '3GPP media' },
  { ext: %w(mp3), icon: 'mp3', name: 'MPEG Layer III (MP3) audio' },
  { ext: %w(ogg oga), icon: 'ogg', name: 'OGG audio' },
  { ext: %w(ts), icon: 'ts', name: 'MPEG transport stream (TS) media' },
  { ext: %w(avi), icon: 'avi', name: 'AVI media' },
  { ext: %w(wav), icon: 'wav', name: 'Waveform Audio File (WAV) audio' },
  { ext: %w(m4a m4b), icon: 'm4a', name: 'MPEG-4 audio' },
  { ext: %w(wmv wma), icon: 'wmv', name: 'Windows Media Video/Audio (WMV/WMA) media' },
  { ext: %w(qt mov), icon: 'qt', name: 'QuickTime media' },
  { ext: %w(flac), icon: 'flac', name: 'Free Lossless Audio Codec (FLAC) audio' },
  { ext: %w(mp4 m4v m4b mpeg mpg), icon: 'mp4', name: 'MPEG-4 video' },
  { ext: %w(dat divx vob amv mxf mcf swf xvid yuv *), icon: 'other_v', name: 'Video file' },
  { ext: %w(aa3 ac3 acm aif aiff ape caf mid midi pcm vox), icon: 'other_a', name: 'Audio file' },
]

ICON_SIZES = [
  { size: 16, name: "icon_16x16.png", orig: 16 },
  { size: 32, name: "icon_16x16@2x.png", orig: 32 },
  { size: 32, name: "icon_32x32.png", orig: 32 },
  { size: 64, name: "icon_32x32@2x.png", orig: 1024 },
  { size: 128, name: "icon_128x128.png", orig: 1024 },
  { size: 256, name: "icon_128x128@2x.png", orig: 1024 },
  { size: 256, name: "icon_256x256.png", orig: 1024 },
  { size: 512, name: "icon_256x256@2x.png", orig: 1024 },
  { size: 512, name: "icon_512x512.png", orig: 1024 },
  { size: 1024, name: "icon_512x512@2x.png", orig: 1024 },
]

def safe_system(*args)
  puts args.shelljoin.colorize(:cyan)
  system(*args) || abort("Fail to run the last command!")
end

def iconset(name, files)
  iconset_folder = File.join ASSETS_PATH, "doc_#{name}.iconset"
  FileUtils.rm_rf iconset_folder
  FileUtils.mkdir iconset_folder
  ICON_SIZES.each do |sz|
    size = sz[:size]
    filename = sz[:name]
    orig = sz[:orig]
    dest = File.join iconset_folder, filename
    if orig == size
      FileUtils.cp files[orig], dest
    else
      safe_system "sips", "-z", size.to_s, size.to_s, files[orig], "--out", dest
    end
  end
end

plist = Plist::parse_xml(INFO_PLIST_PATH)

doc_types = []

FT_DATA.each do |data|
  # generate iconset
  icon_name = data[:icon]
  icon_files = {
    1024 => File.join(ICON_PATH, "doc_#{icon_name}.png"),
    16 => File.join(ICON_PATH, "doc_#{icon_name}_16.png"),
    32 => File.join(ICON_PATH, "doc_#{icon_name}_32.png"),
  }
  iconset icon_name, icon_files
  
  # write into plist
  ft_node = Hash.new.tap do |n|
    n["CFBundleTypeExtensions"] = data[:ext]
    n["CFBundleTypeIconFile"] = "doc_#{icon_name}.icns"
    n["CFBundleTypeName"] = data[:name]
    n["CFBundleTypeRole"] = "Viewer"
    n["LSTypeIsPackage"] = false
    n["NSPersistentStoreTypeKey"] = "XML"
  end
  doc_types << ft_node
end

plist["CFBundleDocumentTypes"] = doc_types

File.write(INFO_PLIST_PATH, plist.to_plist)
