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
      
      # Marca como já carregados
      @loaded_modules = {
        'FaceToBoard' => true,
        'ResetUCS' => true,
        'IntelligentWorkflow' => true,
        'MaterialSystem' => true,
        'StampConfigManager' => true
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
      # 'FaceToBoard', 'ResetUCS', 'IntelligentWorkflow', 'MaterialSystem', 'StampConfigManager'
      
      'FlipUCS' => 'lib/flip_ucs',
      'RenameEntities' => 'lib/rename_entities',
      'RotateLocalAxisSelectionCenter' => 'lib/rotate_local_axis_selection_center',
      'StampName' => 'lib/stamp_name',
      'SelectStamps' => 'lib/select_stamps',
      'GroupToComponent' => 'lib/group_to_component',
      'UpdateStamps' => 'lib/update_stamps',
      'LaserEngraving' => 'lib/laser_engraving',
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

    # ===== 👁️ OBSERVER DE SELEÇÃO =====
    class AppSelectionObserver < Sketchup::SelectionObserver
      def onSelectionBulkChange(selection)
        Rjv::MockupTools.check_and_update_selection_info if Rjv::MockupTools.selector_dialog&.visible?
      end

      def onSelectionCleared(selection)
        Rjv::MockupTools.check_and_update_selection_info if Rjv::MockupTools.selector_dialog&.visible?
      end
    end

    @selector_dialog_instance = nil
    def self.selector_dialog; @selector_dialog_instance; end

    # ===== 🔄 ATUALIZAÇÃO DE INFORMAÇÕES DO SELETOR =====
    def self.check_and_update_selection_info
      return unless @selector_dialog_instance&.visible?
      
      # Garante que módulos necessários estejam carregados
      ensure_loaded('UpdateStamps')
      ensure_loaded('LaserEngraving')
      ensure_loaded('MirrorHandler')
      ensure_loaded('ScaleHandler')
      # MaterialSystem já está carregado no início
      
      model = Sketchup.active_model
      
      updates_pending_count = 0
      pending_engravings_count = 0
      makette_total_count = 0
      mirrored_makette_count = 0
      
      begin
        updates_pending_count = Rjv::MockupTools::UpdateStamps.check_for_updates
      rescue => e
        puts "Erro ao verificar updates de carimbos: #{e.message}"
      end
      
      begin
        pending_engravings_count = Rjv::MockupTools::LaserEngraving.check_for_pending_engravings
      rescue => e
        puts "Erro ao verificar gravações pendentes: #{e.message}"
      end

      begin
        makette_total_count = self.count_makette_pro_pieces
      rescue => e
        puts "Erro ao contar peças MakettePro: #{e.message}"
      end
      
      begin
        mirrored_makette_count = Rjv::MockupTools::MirrorHandler.find_mirrored_makette_pro(model.active_entities).count
      rescue => e
        puts "Erro ao verificar peças espelhadas: #{e.message}"
      end
    
      scaled_makette_count = Rjv::MockupTools::ScaleHandler.find_scaled_makette_pro(model.active_entities).count

      selection = model.selection
      s_empty = selection.empty? 
      
      tool_states = {
        'face_to_board' => !s_empty && selection.any? { |e| e.is_a?(Sketchup::Face) },
        'reset_ucs' => !s_empty && selection.any? { |e| e.is_a?(Sketchup::ComponentInstance) },
        'flip_ucs' => !s_empty && selection.any? { |e| e.is_a?(Sketchup::ComponentInstance) },
        'rename_entities' => !s_empty,
        'rot_x' => !s_empty, 'rot_y' => !s_empty, 'rot_z' => !s_empty,
        'apply_stamp_native' => !s_empty,
        'select_stamps' => true,
        'group_to_component' => !s_empty && selection.any? { |e| e.is_a?(Sketchup::Group) },
        'update_stamps' => true,
        'planifier' => !s_empty,
        'color_manager' => true,
        'create_engraving' => !s_empty && selection.any? { |e| e.is_a?(Sketchup::ComponentInstance) && e.definition.get_attribute("MakettePro", "identifier") == "MakettePro" },
        'collision_analyzer' => true,
        'intelligent_workflow' => true
      }
      
      entity_info = { count: selection.count, is_mixed: false, makette_pro_count: 0 }
      makette_count = 0
      count_proc = ->(entities) { 
        entities.each do |ent|
          if ent.is_a?(Sketchup::ComponentInstance)
            makette_count += 1 if ent.definition.get_attribute("MakettePro", "identifier") == "MakettePro"
            count_proc.call(ent.definition.entities)
          elsif ent.is_a?(Sketchup::Group)
            count_proc.call(ent.entities)
          end
        end
      }
      count_proc.call(selection)
      entity_info[:makette_pro_count] = makette_count
      
      first_def = !s_empty && selection.first.respond_to?(:definition) ? selection.first.definition : nil
      all_same_def = !s_empty && first_def && selection.all? { |e| e.respond_to?(:definition) && e.definition == first_def }
      
      if s_empty
        # no info
      elsif all_same_def
        entity = selection.first
        entity_info[:type_name] = entity.typename
        entity_info[:layer_name] = entity.layer.name if entity.layer
        if entity.material
          entity_info[:material_name] = entity.material.name
          entity_info[:material_color] = entity.material.color.to_s
        end
        if entity.respond_to?(:definition) && entity.definition
          entity_info[:instance_name] = (selection.count > 1) ? "(Múltiplos)" : entity.name
          entity_info[:definition_name] = entity.definition.name
          entity_info[:total_in_model] = entity.definition.count_instances
        end
      else
        entity_info[:is_mixed] = true unless selection.count <= 1
        if selection.count == 1
          entity = selection.first
          entity_info[:type_name] = entity.typename
          entity_info[:layer_name] = entity.layer.name if entity.layer
          if entity.respond_to?(:material) && entity.material
            entity_info[:material_name] = entity.material.name
            entity_info[:material_color] = entity.material.color.to_s
          end
        end
      end
      
      contextual_finishes = Rjv::MockupTools::MaterialSystem.get_contextual_finishes_for_selector(selection)
      
      ui_data = { 
        tool_states: tool_states, 
        entity_info: entity_info, 
        pending_engravings_count: pending_engravings_count,
        updates_pending_count: updates_pending_count,
        contextual_finishes: contextual_finishes,
        makette_total_count: makette_total_count,
        mirrored_makette_count: mirrored_makette_count,
        scaled_makette_count: scaled_makette_count
      }
      
      @selector_dialog_instance.execute_script("updateUI(#{ui_data.to_json})")
    end

    # ===== 💬 DIÁLOGO SELETOR =====
    def self.open_selector_dialog
      # MaterialSystem já está carregado no início
      
      if @selector_dialog_instance&.visible?
        @selector_dialog_instance.bring_to_front
        return
      end
      
      dialog_style = UI::HtmlDialog::STYLE_DIALOG
      if Sketchup.version.to_i >= 17
        begin
          UI::HtmlDialog.const_get('STYLE_PALETTE')
          dialog_style = UI::HtmlDialog::STYLE_PALETTE
        rescue NameError
          begin
            UI::HtmlDialog.const_get('STYLE_WINDOW')
            dialog_style = UI::HtmlDialog::STYLE_WINDOW
          rescue NameError
            dialog_style = UI::HtmlDialog::STYLE_DIALOG
          end
        end
      end
      
      dialog_options = {
        dialog_title: "MakettePro", 
        preferences_key: "RjvMockupTools_SelectorDialog", 
        scrollable: true, 
        resizable: true, 
        width: 350, 
        height: 750, 
        style: dialog_style
      }
      
      @selector_dialog_instance = UI::HtmlDialog.new(dialog_options)
      html_path = File.join(PLUGIN_ROOT_DIR, 'html', 'selector_dialog.html')
      @selector_dialog_instance.set_file(html_path)
      
      @selector_dialog_instance.add_action_callback("save_preference") do |dialog, key, value|
        Sketchup.write_default("RjvMockupTools_Selector", key, value)
      end
      
      @selector_dialog_instance.add_action_callback("get_preference") do |_, key|
        value = Sketchup.read_default("RjvMockupTools_Selector", key, "100%")
        @selector_dialog_instance.execute_script("applySavedScale('#{value}')")
      end
      
      @selector_dialog_instance.add_action_callback("load_selector_data") do |_,_|
        properties = Rjv::MockupTools::MaterialSystem.property_manager.properties
        script = "populateSelector(#{properties.to_json})"
        @selector_dialog_instance.execute_script(script)
        true
      end
      
      @selector_dialog_instance.add_action_callback("apply_material") { |_, d| 
        Rjv::MockupTools::MaterialSystem.execute_material_action(JSON.parse(d, symbolize_names: true))
        true 
      }
      
      @selector_dialog_instance.add_action_callback("apply_finish") { |_, d| 
        Rjv::MockupTools::MaterialSystem.execute_finish_action(JSON.parse(d, symbolize_names: true))
        true 
      }
      
      @selector_dialog_instance.add_action_callback("open_manager") { |_,_| 
        Rjv::MockupTools::MaterialSystem.open_property_editor
        true 
      }
      
      @selector_dialog_instance.add_action_callback("get_selection_info") { |_,_| 
        self.check_and_update_selection_info
        true 
      }
      
      @selector_dialog_instance.add_action_callback("run_command") { |_, cmd| 
        (lambda_cmd = COMMAND_MAP[cmd])&.call
        true 
      }
      
      @selector_dialog_instance.add_action_callback("configure_stamp") do |_, _|
        ensure_loaded('StampName')
        Rjv::MockupTools::StampName.configure_stamp_settings
        true
      end
      
      @selector_dialog_instance.add_action_callback("run_intelligent_workflow_with_material") do |_ctx, material_json|
        begin
          # IntelligentWorkflow já está carregado no início
          
          material_data = JSON.parse(material_json, symbolize_names: true)
          thickness_cm = material_data[:thickness].to_f
          thickness_mm = thickness_cm * 10.0
          
          result = Rjv::MockupTools::IntelligentWorkflow.run_intelligent_workflow({
            material_name: material_data[:name],
            thickness_mm: thickness_mm,
            silent: false,
            debug: false,
            material_auto_detect: false
          })
          
        rescue => e
          UI.messagebox("Erro no workflow: #{e.message}")
          puts "Erro no workflow inteligente: #{e.message}"
          puts e.backtrace.first(3)
        end
        
        true
      end
      
      @selector_dialog_instance.set_on_closed { @selector_dialog_instance = nil }
      @selector_dialog_instance.show
    end

    # ===== 🚀 INICIALIZAÇÃO DO PLUGIN =====
    unless file_loaded?(__FILE__)
      Sketchup.active_model.selection.add_observer(AppSelectionObserver.new)
      Rjv::MockupTools::ToolbarSystem.initialize_toolbars
      Menus.create_ui

      puts "🚀 #{full_version_string} inicializado (LAZY LOADING ativado)!"
      file_loaded(__FILE__)
    end 
  end 
end