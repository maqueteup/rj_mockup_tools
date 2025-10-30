# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module Rjv
  module MockupTools
    module StampConfigManager
      extend self

      CONFIG_JSON_PATH = File.join(Rjv::MockupTools::PLUGIN_ROOT_DIR, 'data', 'stamp_config.json').freeze
      
      DEFAULT_SETTINGS = {
        fontName: "Arial",
        fontSize: 3.0,
        offsetX: 3.0,
        offsetY: 3.0
      }.freeze

      def load_settings
        data_dir = File.dirname(CONFIG_JSON_PATH)
        Dir.mkdir(data_dir) unless Dir.exist?(data_dir)
        if File.exist?(CONFIG_JSON_PATH)
          begin
            json_data = File.read(CONFIG_JSON_PATH)
            DEFAULT_SETTINGS.merge(JSON.parse(json_data, symbolize_names: true))
          rescue
            DEFAULT_SETTINGS
          end
        else
          DEFAULT_SETTINGS
        end
      end

      def save_settings(settings_hash)
        begin
          File.write(CONFIG_JSON_PATH, JSON.pretty_generate(settings_hash))
          true
        rescue => e
          UI.messagebox("Erro ao salvar configurações do carimbo: #{e.message}")
          false
        end
      end
    end
  end
end