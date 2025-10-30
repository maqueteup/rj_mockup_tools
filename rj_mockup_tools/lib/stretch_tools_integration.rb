# lib/stretch_tools_integration.rb
# encoding: UTF-8

# Carrega as duas ferramentas
require_relative 'stretch_tool_simple'
require_relative 'stretch_face_tool'

module Rjv
  module MockupTools
    module StretchTools
      extend self

      # Instâncias das ferramentas
      @@stretch_tool = nil
      @@stretch_face_tool = nil

      def self.get_stretch_tool
        @@stretch_tool ||= StretchTool.new
      end

      def self.get_stretch_face_tool
        @@stretch_face_tool ||= StretchFaceTool.new
      end

      # Ativa a ferramenta de stretch por bounding box
      def self.activate_stretch_tool
        model = Sketchup.active_model
        tool = get_stretch_tool
        model.select_tool(tool)
        puts "Ferramenta Stretch (Bounding Box) ativada"
      end

      # Ativa a ferramenta de stretch por face personalizada
      def self.activate_stretch_face_tool
        model = Sketchup.active_model
        tool = get_stretch_face_tool
        model.select_tool(tool)
        puts "Ferramenta Stretch Face (Face Personalizada) ativada"
      end

      # Criação dos comandos para as toolbars
      def self.create_commands
        commands = {}

        # Comando para Stretch normal (Bounding Box)
        commands[:stretch_bbox] = UI::Command.new("Stretch (Bounding Box)") do
          activate_stretch_tool
        end
        commands[:stretch_bbox].tooltip = "Stretch usando faces da bounding box\n(Ctrl = modo bidirecional)"
        commands[:stretch_bbox].status_bar_text = "Stretch baseado nas faces da bounding box da seleção"
        commands[:stretch_bbox].small_icon = File.join(PLUGIN_ROOT_DIR, "icons", "24x24", "stretch_tool.png")
        commands[:stretch_bbox].large_icon = File.join(PLUGIN_ROOT_DIR, "icons", "32x32", "stretch_tool.png")

        # Comando para Stretch Face (Face Personalizada)
        commands[:stretch_face] = UI::Command.new("Stretch (Face Custom)") do
          activate_stretch_face_tool
        end
        commands[:stretch_face].tooltip = "Stretch usando face personalizada do modelo\n(Alt = bilateral, Ctrl = bidirecional)"
        commands[:stretch_face].status_bar_text = "Stretch baseado em face selecionada da geometria"
        
        # Ícone específico para face tool (vamos criar um diferente)
        commands[:stretch_face].small_icon = File.join(PLUGIN_ROOT_DIR, "icons", "24x24", "stretch_face_tool.png")
        commands[:stretch_face].large_icon = File.join(PLUGIN_ROOT_DIR, "icons", "32x32", "stretch_face_tool.png")

        commands
      end

      # Adiciona ao menu principal
      def self.add_to_menu(menu)
        submenu = menu.add_submenu("🔧 Stretch Tools")
        
        commands = create_commands
        
        submenu.add_item(commands[:stretch_bbox])
        submenu.add_separator
        submenu.add_item(commands[:stretch_face])
        
        puts "Menu Stretch Tools criado com sucesso!"
      end

      # Adiciona à toolbar (se existir)
      def self.add_to_toolbar(toolbar)
        commands = create_commands
        
        # Adiciona ambos os comandos à toolbar
        toolbar.add_item(commands[:stretch_bbox])
        toolbar.add_item(commands[:stretch_face])
        
        puts "Comandos Stretch adicionados à toolbar!"
      end

      # Cria toolbar específica para stretch
      def self.create_stretch_toolbar
        toolbar = UI::Toolbar.new("RJV Stretch Tools")
        
        commands = create_commands
        
        toolbar.add_item(commands[:stretch_bbox])
        toolbar.add_separator
        toolbar.add_item(commands[:stretch_face])
        
        # Mostra a toolbar
        toolbar.show if toolbar.count > 0
        
        puts "Toolbar Stretch Tools criada!"
        return toolbar
      end

      # Método para criar ícones específicos se não existirem
      def self.ensure_icons_exist
        # Caminho base dos ícones
        icons_base = File.join(PLUGIN_ROOT_DIR, "icons")
        
        sizes = ["16x16", "24x24", "32x32"]
        
        sizes.each do |size|
          # Ícone para stretch face tool
          face_icon_path = File.join(icons_base, size, "stretch_face_tool.png")
          
          unless File.exist?(face_icon_path)
            # Copia o ícone padrão como fallback
            default_icon = File.join(icons_base, size, "stretch_tool.png")
            if File.exist?(default_icon)
              begin
                FileUtils.copy(default_icon, face_icon_path)
                puts "✅ Ícone stretch_face_tool.png criado para #{size}"
              rescue => e
                puts "❌ Erro ao criar ícone #{size}/stretch_face_tool.png: #{e.message}"
              end
            end
          end
        end
      end

      # Método de inicialização
      def self.initialize_stretch_tools
        puts "\n🔧 Inicializando Stretch Tools..."
        
        # Garante que os ícones existem
        ensure_icons_exist
        
        # Cria toolbar específica (opcional)
        # create_stretch_toolbar
        
        puts "✅ Stretch Tools inicializadas com sucesso!"
        puts "   - StretchTool (Bounding Box): Faces virtuais da seleção"
        puts "   - StretchFaceTool (Face Custom): Face personalizada do modelo"
      end
    end
  end
end

# Exemplo de como integrar no sistema principal
unless defined?(STRETCH_TOOLS_LOADED)
  # Inicializa as ferramentas
  Rjv::MockupTools::StretchTools.initialize_stretch_tools
  
  # Marca como carregado
  STRETCH_TOOLS_LOADED = true
  
  puts "🎯 Stretch Tools integradas ao sistema RJV MockupTools!"
end