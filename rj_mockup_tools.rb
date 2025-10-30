# rj_mockup_tools.rb (Arquivo Loader/Registrador)
# encoding: UTF-8

require 'sketchup.rb'
require 'extensions.rb'

# Carrega informações de versão centralizada
require_relative 'rj_mockup_tools/lib/version'

module Rjv
  module MockupTools
    # Cria a extensão no gerenciador do SketchUp
    extension = SketchupExtension.new(
      PLUGIN_NAME,
      'rj_mockup_tools/main.rb'
    )

    extension.description = PLUGIN_DESCRIPTION
    extension.version     = VERSION
    extension.creator     = PLUGIN_CREATOR
    extension.copyright   = "#{Time.now.year}, Todos os direitos reservados"

    Sketchup.register_extension(extension, true)
  end
end