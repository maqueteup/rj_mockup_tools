#!/usr/bin/env ruby
# encoding: UTF-8

require 'json'
require 'fileutils'

def round_floats(obj, precision = 3)
  case obj
  when Hash
    obj.transform_values { |v| round_floats(v, precision) }
  when Array
    obj.map { |v| round_floats(v, precision) }
  when Float
    obj.round(precision)
  else
    obj
  end
end

files = Dir.glob('rj_mockup_tools/data/*.json')
files.each do |file|
  puts "Processando: #{File.basename(file)}"

  begin
    data = JSON.parse(File.read(file))
    rounded = round_floats(data)
    File.write(file, JSON.pretty_generate(rounded))
    puts "OK: #{File.basename(file)}"
  rescue => e
    puts "ERRO em #{File.basename(file)}: #{e.message}"
  end
end

puts "\nTodos os arquivos JSON foram processados!"
