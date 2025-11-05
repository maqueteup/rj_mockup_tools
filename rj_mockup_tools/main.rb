# rj_mockup_tools/main.rb (OTIMIZADO com Lazy Loading)
# encoding: UTF-8

module Rjv
  module MockupTools

    PLUGIN_ROOT_DIR = File.dirname(__FILE__) unless defined?(Rjv::MockupTools::PLUGIN_ROOT_DIR)

    # Carrega informações de versão centralizada
    require_relative 'lib/version'
    
    # ===== 🚀 LAZY LOADING - Carrega apenas o essencial =====
    # Arquivos críticos que precisam estar carregados no início:
    begin
      # Sistemas essenciais
      require_relative 'lib/makettepro_toolbars'
      require_relative 'lib/menus'
      
      # ✅ Módulos que outros módulos dependem (carrega no início)
      require_relative 'lib/face_to_board_improved'
      require_relative 'lib/reset_ucs_improved'
      require_relative 'lib/component_axes_reset'
      require_relative 'lib/sheet_detector'
      require_relative 'lib/intelligent_workflow'
      require_relative 'lib/material_manager_tool'
      require_relative 'lib/stamp_config_manager'  # ✅ ADICIONADO para StampName
      require_relative 'lib/group_to_component'    # ✅ Carrega GroupToComponent no início (mas oculto da UI)

      # Marca como já carregados
      @loaded_modules = {
        'FaceToBoard' => true,
        'ResetUCS' => true,
        'IntelligentWorkflow' => true,
        'MaterialSystem' => true,
        'StampConfigManager' => true,
        'GroupToComponent' => true
      }
      
      puts "✅ Módulos essenciais carregados"
    rescue LoadError => e
      UI.messagebox("Erro FATAL ao carregar biblioteca essencial: #{e.message}")
      puts e.backtrace.join("\n")
      raise e
    end

    # ===== 📦 MAPA DE MÓDULOS (carregados sob demanda) =====
    MODULE_FILES = {
      # Módulos já carregados no início (não precisam de lazy loading):
      # 'FaceToBoard', 'ResetUCS', 'IntelligentWorkflow', 'MaterialSystem', 'StampConfigManager', 'GroupToComponent'

      'FlipUCS' => 'lib/flip_ucs',
      'RenameEntities' => 'lib/rename_entities',
      'RotateLocalAxisSelectionCenter' => 'lib/rotate_local_axis_selection_center',
      'StampName' => 'lib/stamp_name',
      'SelectStamps' => 'lib/select_stamps',
      'UpdateStamps' => 'lib/update_stamps',
      'LaserEngraving' => 'lib/laser_engraving',
      'Apply3DPrint' => 'lib/apply_3d_print',
      'Planifier' => 'lib/planifier',
      'ReportGenerator' => 'lib/report_generator',
      'MaterialColorManager' => 'lib/material_color_manager',
      'CollisionAnalyzer' => 'lib/collision_analyzer',
      'ColorByLayerToggle' => 'lib/color_by_layer_toggle',
      'StretchTool' => 'lib/stretch_tool',
      'StretchFaceTool' => 'lib/stretch_face_tool',
      'MirrorHandler' => 'lib/mirror_handler',
      'ScaleHandler' => 'lib/scale_handler',
      'PanelDividerTool' => 'lib/panel_divider_tool',
      'ModelInspector' => 'lib/model_inspector'
    }
    
    @loaded_modules ||= {}
    
    # ===== 🔄 AUTOLOAD - Carrega módulos automaticamente quando necessário =====
    def self.ensure_loaded(module_name)
      return true if @loaded_modules[module_name]
      
      file_path = MODULE_FILES[module_name]
      return false unless file_path
      
      begin
        require_relative file_path
        @loaded_modules[module_name] = true
        puts "✅ Módulo carregado sob demanda: #{module_name}"
        true
      rescue LoadError => e
        puts "❌ Erro ao carregar #{module_name}: #{e.message}"
        false
      end
    end

    # ===== 🎯 COMMAND MAP (com lazy loading) =====
    COMMAND_MAP = {
      # Comandos com módulos já carregados (sem ensure_loaded):
      'face_to_board' => -> { 
        Rjv::MockupTools::FaceToBoard.run 
      },
      'reset_ucs' => -> { 
        Rjv::MockupTools::ResetUCS.run 
      },
      'intelligent_workflow' => -> { 
        Rjv::MockupTools::IntelligentWorkflow.run 
      },
      
      # Comandos com lazy loading:
      'flip_ucs' => -> { 
        ensure_loaded('FlipUCS')
        Rjv::MockupTools::FlipUCS.run 
      },
      'rename_entities' => -> { 
        ensure_loaded('RenameEntities')
        Rjv::MockupTools::RenameEntities.run 
      },
      'rot_x' => -> { 
        ensure_loaded('RotateLocalAxisSelectionCenter')
        Rjv::MockupTools::RotateLocalAxisSelectionCenter.rotate_local_x 
      },
      'rot_y' => -> { 
        ensure_loaded('RotateLocalAxisSelectionCenter')
        Rjv::MockupTools::RotateLocalAxisSelectionCenter.rotate_local_y 
      },
      'rot_z' => -> { 
        ensure_loaded('RotateLocalAxisSelectionCenter')
        Rjv::MockupTools::RotateLocalAxisSelectionCenter.rotate_local_z 
      },
      'apply_stamp_native' => -> { 
        ensure_loaded('StampName')
        Rjv::MockupTools::StampName.run 
      },
      'select_stamps' => -> { 
        ensure_loaded('SelectStamps')
        Rjv::MockupTools::SelectStamps.select_all_stamps 
      },
      'group_to_component' => -> { 
        ensure_loaded('GroupToComponent')
        Rjv::MockupTools::GroupToComponent.convert_groups_with_axes_reset() 
      },
      'update_stamps' => -> { 
        ensure_loaded('UpdateStamps')
        Rjv::MockupTools::UpdateStamps.run 
      },
      'fix_pending_stamps' => -> { 
        ensure_loaded('UpdateStamps')
        Rjv::MockupTools::UpdateStamps.fix_pending_stamps 
      },
      'planifier' => -> { 
        ensure_loaded('Planifier')
        Rjv::MockupTools::Planifier.run 
      },
      'generate_report' => -> { 
        ensure_loaded('ReportGenerator')
        Rjv::MockupTools::ReportGenerator.generate_layout_report 
      },
      'color_manager' => -> { 
        ensure_loaded('MaterialColorManager')
        Rjv::MockupTools::MaterialColorManager.open_dialog 
      },
      'create_engraving' => -> { 
        ensure_loaded('LaserEngraving')
        Rjv::MockupTools::LaserEngraving.run_on_selection 
      },
      'create_all_engravings' => -> { 
        ensure_loaded('LaserEngraving')
        Rjv::MockupTools::LaserEngraving.run_on_all_pending 
      },
      'collision_analyzer' => -> { 
        ensure_loaded('CollisionAnalyzer')
        Rjv::MockupTools::CollisionAnalyzer.open_dialog 
      },
      'select_mirrored' => -> { 
        ensure_loaded('MirrorHandler')
        Rjv::MockupTools::MirrorHandler.select_mirrored 
      },
      'fix_all_mirrored' => -> { 
        ensure_loaded('MirrorHandler')
        Rjv::MockupTools::MirrorHandler.fix_all_mirrored 
      },
      'select_scaled' => -> { 
        ensure_loaded('ScaleHandler')
        Rjv::MockupTools::ScaleHandler.select_scaled 
      },
      'fix_selected_scaled' => -> { 
        ensure_loaded('ScaleHandler')
        Rjv::MockupTools::ScaleHandler.fix_selected_scaled 
      },
      'model_inspector' => -> { 
        ensure_loaded('ModelInspector')
        Rjv::MockupTools::ModelInspector.open_dialog 
      }
    }

    # ===== 📊 CONTADOR DE PEÇAS MAKETTEPRO =====
    def self.count_makette_pro_pieces
      count = 0
      recursive_count = ->(entities, parents) {
        entities.each do |ent|
          if ent.is_a?(Sketchup::Group)
            recursive_count.call(ent.entities, parents + [ent])
          elsif ent.is_a?(Sketchup::ComponentInstance)
            if ent.definition.get_attribute("MakettePro", "identifier") == "MakettePro"
              is_in_plan_group = parents.any? { |p| p.name.downcase.include?("planifica") || p.name.downcase.include?("plano de corte") }
              count += 1 unless is_in_plan_group
            end
            recursive_count.call(ent.definition.entities, parents + [ent])
          end
        end
      }
      recursive_count.call(Sketchup.active_model.entities, [])
      return count
    end

    # ===== REMOVIDO: Seletor de Ferramentas =====
    # O seletor de ferramentas (selector_dialog) foi removido.
    # Use as toolbars e menus para acessar as funcionalidades.

    # ===== 🚀 INICIALIZAÇÃO DO PLUGIN =====
    unless file_loaded?(__FILE__)
      Rjv::MockupTools::ToolbarSystem.initialize_toolbars
      Menus.create_ui

      puts "🚀 #{full_version_string} inicializado (LAZY LOADING ativado)!"
      file_loaded(__FILE__)
    end 
  end 
end