# lib/makettepro_toolbars.rb (OTIMIZADO - Inicialização Rápida)
# encoding: UTF-8

require_relative 'icon_tooltip_feedback'

module Rjv
  module MockupTools
    module ToolbarSystem
      
      # ===== CONFIGURAÇÃO SIMPLIFICADA =====
      TOOLBAR_CONFIG = {
        main: {
          name: "MakettePro",
          tools: [:reset_ucs, :reset_ucs_interactive, :flip_ucs, :flip_ucs_interactive, :rename_entities, :rotate_x, :rotate_y, :rotate_z],
          always_visible: true,
          priority: 1  # ✅ Cria primeiro
        },
        engraving: {
          name: "MakettePro - Gravação",
          tools: [:create_engraving, :create_all_engravings, :apply_stamp, :configure_stamp, :select_stamps, :update_stamps],
          always_visible: true,
          priority: 2
        },
        materials: {
          name: "MakettePro - Materiais",
          tools: [],
          always_visible: true,
          priority: 3  # ✅ Cria após as principais
        },
        analysis: {
          name: "MakettePro - Análise",
          tools: [:color_manager, :apply_3d_print, :planifier, :generate_report, :collision_analyzer, :color_by_layer, :stretch_tool, :stretch_face_tool],
          always_visible: true,
          priority: 3,
          lazy: true  # ✅ Carrega sob demanda
        },
        management: {
          name: "MakettePro - Gerenciamento",
          tools: [:material_manager],
          always_visible: true,
          priority: 4,
          lazy: true  # ✅ Carrega sob demanda
        }
      }

      # ===== MAPEAMENTO DE COMANDOS =====
      TOOL_COMMANDS = {
        face_to_board: "face_to_board",
        group_to_component: "group_to_component",
        reset_ucs: "reset_ucs",
        reset_ucs_interactive: "reset_ucs_interactive",
        flip_ucs: "flip_ucs",
        flip_ucs_interactive: "flip_ucs_interactive",
        rename_entities: "rename_entities",
        rotate_x: "rot_x",
        rotate_y: "rot_y",
        rotate_z: "rot_z",
        create_engraving: "create_engraving",
        create_all_engravings: "create_all_engravings",
        apply_stamp: "apply_stamp_native",
        configure_stamp: "configure_stamp",
        select_stamps: "select_stamps",
        update_stamps: "update_stamps",
        color_manager: "color_manager",
        apply_3d_print: "apply_3d_print",
        planifier: "planifier",
        generate_report: "generate_report",
        collision_analyzer: "collision_analyzer",
        color_by_layer: "color_by_layer_toggle",
        stretch_tool: "stretch_tool",
        stretch_face_tool: "stretch_face_tool",
        material_manager: "material_manager"
      }

      # ===== CLASSE PRINCIPAL OTIMIZADA =====
      class ToolbarManager
        
        def initialize
          @toolbars = {}
          @materials_data = []
          @plugin_dir = File.dirname(__FILE__)
          @icon_cache = {}  # ✅ Cache de ícones
          @lazy_toolbars_created = {}
          
          Rjv::MockupTools::IconTooltipFeedback.initialize
          
          setup_simple_icon_structure
          
          # ✅ CRIA APENAS TOOLBARS PRIORITÁRIAS
          create_priority_toolbars
          
          # ✅ ADIA CRIAÇÃO DAS OUTRAS TOOLBARS
          UI.start_timer(2.0, false) do
            create_lazy_toolbars
          end
          
          puts "⚡ MakettePro: Inicialização rápida completa!"
        end
        
        def setup_simple_icon_structure
          @icons_path = File.join(@plugin_dir, '..', 'icons')
          Dir.mkdir(@icons_path) unless Dir.exist?(@icons_path)
          
          material_icons_path = File.join(@icons_path, 'material_config_icons')
          Dir.mkdir(material_icons_path) unless Dir.exist?(material_icons_path)
        end
        
        # ✅ CRIA APENAS TOOLBARS ESSENCIAIS NO INÍCIO
        def create_priority_toolbars
          # Separa toolbars por prioridade
          sorted_toolbars = TOOLBAR_CONFIG.sort_by { |key, config| config[:priority] || 99 }
          
          sorted_toolbars.each do |toolbar_key, config|
            # Pula lazy toolbars e materials
            next if config[:lazy]
            next if toolbar_key == :materials  # ✅ Materials será criada depois
            
            create_toolbar(toolbar_key)
          end
        end
        
        # ✅ CRIA TOOLBARS SECUNDÁRIAS DEPOIS
        def create_lazy_toolbars
          lazy_toolbars = TOOLBAR_CONFIG
            .select { |key, config| config[:lazy] }
            .sort_by { |key, config| config[:priority] || 99 }
          
          lazy_toolbars.each do |toolbar_key, config|
            next if @lazy_toolbars_created[toolbar_key]
            create_toolbar(toolbar_key, config[:always_visible])
            @lazy_toolbars_created[toolbar_key] = true
          end
          
          # ✅ Cria e carrega materiais (SEM placeholder)
          load_materials_deferred
        end
        
        def create_toolbar(toolbar_key, visible = nil)
          config = TOOLBAR_CONFIG[toolbar_key]
          return unless config
          
          visible = config[:always_visible] if visible.nil?
          
          toolbar = UI::Toolbar.new(config[:name])
          
          config[:tools].each do |tool_key|
            add_tool_to_toolbar(toolbar, tool_key)
          end
          
          toolbar.show if visible
          @toolbars[toolbar_key] = toolbar
        end
        
        def add_tool_to_toolbar(toolbar, tool_key)
          command_name = TOOL_COMMANDS[tool_key]
          return unless command_name
          
          tooltip = get_tool_tooltip(tool_key)
          
          cmd = UI::Command.new(tooltip) {
            execute_tool_command(command_name, tool_key)
          }
          
          cmd.tooltip = tooltip
          cmd.status_bar_text = tooltip
          cmd.menu_text = tooltip
          
          # ✅ USA CACHE DE ÍCONES
          icon_path = get_icon_path_cached(tool_key)
          if icon_path
            cmd.small_icon = icon_path
            cmd.large_icon = icon_path
          end
          
          case tool_key
          when :create_engraving, :create_all_engravings
            Rjv::MockupTools::IconTooltipFeedback.register_engraving_command(cmd)
          when :update_stamps
            Rjv::MockupTools::IconTooltipFeedback.register_update_command(cmd)
          end
          
          toolbar.add_item(cmd)
        end
        
        # ✅ CACHE DE ÍCONES
        def get_icon_path_cached(tool_key)
          return @icon_cache[tool_key] if @icon_cache.key?(tool_key)
          
          icon_path = get_icon_path(tool_key)
          @icon_cache[tool_key] = icon_path
          icon_path
        end
        
        def get_icon_path(tool_key)
          icon_formats = ['png', 'svg', 'jpg', 'gif']
          
          icon_formats.each do |format|
            icon_path = File.join(@icons_path, "#{tool_key}.#{format}")
            return icon_path if File.exist?(icon_path)
          end
          
          nil
        end
        
        def get_tool_tooltip(tool_key)
          tooltips = {
            face_to_board: "Placa a partir da Face",
            group_to_component: "Grupo para Componente",
            reset_ucs: "Resetar Eixos (UCS)",
            reset_ucs_interactive: "Resetar Eixos (Escolher Canto)",
            flip_ucs: "Inverter Eixo Z (UCS)",
            flip_ucs_interactive: "Inverter Eixo Z (Interativo)",
            rename_entities: "Renomear Entidades",
            rotate_x: "Rotacionar Eixo X +90°",
            rotate_y: "Rotacionar Eixo Y +90°",
            rotate_z: "Rotacionar Eixo Z +90°",
            create_engraving: "Gerar Gravação a Laser",
            create_all_engravings: "Gerar Todas as Gravações",
            apply_stamp: "Aplicar Carimbo",
            configure_stamp: "Configurar Carimbo",
            select_stamps: "Selecionar Carimbos",
            update_stamps: "Atualizar Carimbos",
            color_manager: "Gerenciador de Cores",
            apply_3d_print: "Aplicar Impressão 3D",
            planifier: "Planificar Peças",
            generate_report: "Gerar Relatório de Planificação",
            collision_analyzer: "Analisador de Colisões",
            color_by_layer: "Cor por Camada",
            stretch_tool: "Stretch (Bounding Box)",
            stretch_face_tool: "Stretch (Face Personalizada)",
            material_manager: "Gerenciador de Materiais"
          }
          
          tooltips[tool_key] || tool_key.to_s.split('_').map(&:capitalize).join(' ')
        end
        
        def execute_tool_command(command_name, tool_key)
          case command_name
          when "configure_stamp"
            Rjv::MockupTools.ensure_loaded('StampName')
            Rjv::MockupTools::StampName.configure_stamp_settings
          when "create_all_engravings"
            Rjv::MockupTools.ensure_loaded('LaserEngraving')
            Rjv::MockupTools::LaserEngraving.run_on_all_pending
          when "color_by_layer_toggle"
            Rjv::MockupTools.ensure_loaded('ColorByLayerToggle')
            Rjv::MockupTools::ColorByLayerToggle.toggle
          when "stretch_tool"
            Rjv::MockupTools.ensure_loaded('StretchTool')
            Sketchup.active_model.select_tool(Rjv::MockupTools::StretchTool.new)
          when "stretch_face_tool"
            Rjv::MockupTools.ensure_loaded('StretchFaceTool')
            Sketchup.active_model.select_tool(Rjv::MockupTools::StretchFaceTool.new)
          when "apply_3d_print"
            Rjv::MockupTools.ensure_loaded('Apply3DPrint')
            Rjv::MockupTools::Apply3DPrint.run
          when "material_manager"
            # MaterialSystem já está carregado no início
            Rjv::MockupTools::MaterialSystem.open_property_editor
          else
            lambda_cmd = Rjv::MockupTools::COMMAND_MAP[command_name]
            lambda_cmd&.call
          end
        end
        
        # ✅ CARREGAMENTO ADIADO DE MATERIAIS
        def load_materials_deferred
          puts "🔄 Iniciando carregamento de materiais..."
          
          begin
            # MaterialSystem já está carregado no início
            properties = Rjv::MockupTools::MaterialSystem.property_manager.properties
            @materials_data = properties[:materials] || []
            
            puts "📦 Materiais carregados: #{@materials_data.length} encontrados"
            
            # ✅ Cria toolbar de materiais pela primeira vez
            create_materials_toolbar
            puts "✅ Toolbar de materiais criada!"
          rescue => e
            puts "❌ Erro ao carregar materiais: #{e.message}"
            puts e.backtrace.first(3)
          end
        end
        
        # ✅ Cria toolbar de materiais (primeira vez)
        def create_materials_toolbar
          puts "🔨 Criando toolbar de materiais..."
          
          toolbar = UI::Toolbar.new("MakettePro - Materiais")
          
          active_materials = @materials_data.select { |m| m[:active] }.sort_by { |m| m[:name] }
          puts "   Materiais ativos: #{active_materials.length}"
          
          if active_materials.empty?
            cmd = UI::Command.new("Nenhum material ativo") { 
              UI.messagebox("Configure materiais no Gerenciador de Materiais")
            }
            cmd.tooltip = "Nenhum material configurado"
            toolbar.add_item(cmd)
          else
            active_materials.each do |material|
              add_material_to_toolbar(toolbar, material)
            end
          end
          
          @toolbars[:materials] = toolbar
          toolbar.show
          
          puts "✅ Toolbar de materiais pronta com #{active_materials.length} materiais"
        end
        
        def load_materials
          # Recarrega os dados de materiais
          begin
            properties = Rjv::MockupTools::MaterialSystem.property_manager.properties
            @materials_data = properties[:materials] || []
            rebuild_materials_toolbar
          rescue => e
            puts "❌ Erro ao recarregar materiais: #{e.message}"
          end
        end
        
        def rebuild_materials_toolbar
          puts "🔨 Reconstruindo toolbar de materiais..."
          
          # ✅ Remove toolbar antiga
          if @toolbars[:materials]
            @toolbars[:materials].hide
            @toolbars[:materials] = nil
          end
          
          # ✅ Cria nova toolbar
          toolbar = UI::Toolbar.new("MakettePro - Materiais")
          
          active_materials = @materials_data.select { |m| m[:active] }.sort_by { |m| m[:name] }
          puts "   Materiais ativos: #{active_materials.length}"
          
          if active_materials.empty?
            cmd = UI::Command.new("Nenhum material ativo") { 
              UI.messagebox("Configure materiais no Gerenciador de Materiais")
            }
            cmd.tooltip = "Nenhum material configurado"
            toolbar.add_item(cmd)
          else
            active_materials.each do |material|
              add_material_to_toolbar(toolbar, material)
            end
          end
          
          @toolbars[:materials] = toolbar
          toolbar.show
          
          puts "✅ Toolbar de materiais reconstruída com #{active_materials.length} materiais"
        end
        
        def add_material_to_toolbar(toolbar, material)
          cmd = UI::Command.new(material[:name]) {
            begin
              # IntelligentWorkflow já está carregado no início
              
              material_data = material
              thickness_cm = material_data[:thickness].to_f
              thickness_mm = thickness_cm * 10.0
              
              result = Rjv::MockupTools::IntelligentWorkflow.run_intelligent_workflow({
                material_name: material_data[:name],
                thickness_mm: thickness_mm,
                silent: false,
                debug: false,
                material_auto_detect: false
              })
              
              if result[:success]
                puts "✅ #{material[:name]} aplicado com sucesso!"
              else
                puts "❌ Erro ao aplicar #{material[:name]}"
              end
              
            rescue => e
              puts "Erro no workflow: #{e.message}"
            end
          }
          
          cmd.tooltip = "Aplicar: #{material[:name]}"
          cmd.status_bar_text = "Aplicar material: #{material[:name]}"
          
          material_icon_path = get_material_icon_path(material)
          if material_icon_path && File.exist?(material_icon_path)
            cmd.small_icon = material_icon_path
            cmd.large_icon = material_icon_path
          end
          
          toolbar.add_item(cmd)
        end
        
        def get_material_icon_path(material)
          safe_name = material[:name].to_s.gsub(/[^a-zA-Z0-9_.-]/, '_').gsub(/\s+/, '_')
          File.join(@icons_path, 'material_config_icons', "#{safe_name}.png")
        end
        
        def refresh_materials
          load_materials
        end
        
        def show_all_toolbars
          @toolbars.each { |key, toolbar| toolbar.show }
        end
        
        def hide_all_toolbars
          @toolbars.each { |key, toolbar| toolbar.hide }
        end
        
        def cleanup
          hide_all_toolbars
          Rjv::MockupTools::IconTooltipFeedback.cleanup
        end
      end
      
      # ===== SINGLETON =====
      @toolbar_manager = nil
      
      def self.initialize_toolbars
        return if @toolbar_manager
        @toolbar_manager = ToolbarManager.new
      end
      
      def self.cleanup
        @toolbar_manager&.cleanup
        @toolbar_manager = nil
      end
      
      def self.refresh_materials
        @toolbar_manager&.refresh_materials
      end
      
      def self.toolbar_manager
        @toolbar_manager
      end
    end
  end
end