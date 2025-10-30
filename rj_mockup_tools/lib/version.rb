# encoding: UTF-8
# version.rb
# Centraliza o versionamento do plugin

module Rjv
  module MockupTools
    # Versão do plugin (formato: MAJOR.MINOR.PATCH)
    VERSION = '3.0.3'.freeze

    # Nome do plugin
    PLUGIN_NAME = 'Mockup Tools RJV'.freeze

    # Autor/Criador
    PLUGIN_CREATOR = 'Roberto Jackson Vieira'.freeze

    # Descrição
    PLUGIN_DESCRIPTION = 'Ferramentas avançadas para criação e análise de mockups, gravação a laser e fabricação'.freeze

    # Informações de versão formatadas
    def self.full_version_string
      "#{PLUGIN_NAME} v#{VERSION}"
    end

    # Informações completas
    def self.info
      {
        name: PLUGIN_NAME,
        version: VERSION,
        creator: PLUGIN_CREATOR,
        description: PLUGIN_DESCRIPTION
      }
    end
  end
end
