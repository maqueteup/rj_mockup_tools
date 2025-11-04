# rj_mockup_tools.rb (Arquivo Loader/Registrador)
# encoding: UTF-8

require 'sketchup.rb'
require 'extensions.rb'

module Rjv
  module MockupTools
    # Cria a extensão no gerenciador do SketchUp
    extension = SketchupExtension.new(
      'Mockup Tools RJV', 
      'rj_mockup_tools/main.rb' # <-- O ponto de entrada principal da sua lógica
    )
    extension.description = 'Ferramentas profissionais para criação e análise de mockups e projetos para fabricação.'
    extension.version     = '3.0.3'
    extension.creator     = 'Roberto Jackson Vieira'
    extension.copyright   = "#{Time.now.year}, Todos os direitos reservados"
    Sketchup.register_extension(extension, true)
  end
end