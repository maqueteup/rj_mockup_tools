# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'base64'

module Rjv
  module MockupTools
    module MaterialSystem
      extend self

      TOLERANCE = 1e-4 unless defined?(self::TOLERANCE)

      # --- PropertyManager ---
      # Gerencia as propriedades de materiais do plugin
      class PropertyManager
        attr_reader :properties

        PROPERTIES_JSON_PATH = File.join(
          Rjv::MockupTools::PLUGIN_ROOT_DIR,
          'data',
          'properties.json'
        )

        def initialize
          data_dir = File.dirname(PROPERTIES_JSON_PATH)
          Dir.mkdir(data_dir) unless Dir.exist?(data_dir)
          @properties = load_properties
        end

        def load_properties
          if File.exist?(PROPERTIES_JSON_PATH)
            begin
              JSON.parse(File.read(PROPERTIES_JSON_PATH), symbolize_names: true)
            rescue JSON::ParserError => e
              puts "Erro ao carregar properties.json: #{e.message}"
              UI.messagebox("AVISO: Erro ao carregar properties.json.\nUsando configuração padrão.")
              { types: [], materials: [] }
            end
          else
            puts "AVISO: properties.json não encontrado. Usando configuração padrão."
            { types: [], materials: [] }
          end
        end

        def update_properties(new_data)
          @properties = new_data
          save_properties
          UI.messagebox("Configurações salvas.\nReinicie o SketchUp para atualizar as barras de ferramentas.")
        end

        private

        def save_properties
          begin
            File.write(PROPERTIES_JSON_PATH, JSON.pretty_generate(@properties))
          rescue => e
            UI.messagebox("Erro ao salvar propriedades: #{e.message}")
            puts "Erro save_properties: #{e.message}"
          end
        end
      end
      @property_manager_instance_ms = nil

      def self.property_manager
        @property_manager_instance_ms ||= PropertyManager.new
      end
      def self.open_property_editor; dialog_style = UI::HtmlDialog::STYLE_DIALOG; if Sketchup.version.to_i >= 17; begin; UI::HtmlDialog.const_get('STYLE_PALETTE'); dialog_style = UI::HtmlDialog::STYLE_PALETTE; rescue NameError; begin; UI::HtmlDialog.const_get('STYLE_WINDOW'); dialog_style = UI::HtmlDialog::STYLE_WINDOW; rescue NameError; dialog_style = UI::HtmlDialog::STYLE_DIALOG; end; end; end; dialog_options = {dialog_title: "RJV: Gerenciador de Materiais", preferences_key: "RjvMockupTools_MaterialManagerDialog", scrollable: false, resizable: true, width: 1000, height: 700, style: UI::HtmlDialog::STYLE_DIALOG}; dialog = UI::HtmlDialog.new(dialog_options); html_path = File.join(Rjv::MockupTools::PLUGIN_ROOT_DIR, 'html', 'property_editor.html'); dialog.set_file(html_path); dialog.set_on_closed {dialog = nil}; dialog.add_action_callback("load_data") { |_ctx| dialog.execute_script("populateData(#{self.property_manager.properties.to_json})"); true }; dialog.add_action_callback("save_icon") { |_ctx, data_json| item = JSON.parse(data_json, symbolize_names: true); save_generated_icon(item); true }; dialog.add_action_callback("cleanup_invalid_icons") { |_ctx| cleanup_invalid_icons; true }; dialog.add_action_callback("save_data") { |_ctx, data_json| updated_properties = JSON.parse(data_json, symbolize_names: true); self.property_manager.update_properties(updated_properties); true }; dialog.add_action_callback("export_data") { |_ctx| fp = UI.savepanel("Exportar JSON", Rjv::MockupTools::PLUGIN_ROOT_DIR, "rjv_materiais.json"); if fp; File.write(fp, JSON.pretty_generate(self.property_manager.properties)); UI.messagebox("Exportado: #{File.basename(fp)}"); end; true }; dialog.add_action_callback("import_data") { |_ctx| fp = UI.openpanel("Importar JSON", Rjv::MockupTools::PLUGIN_ROOT_DIR, "Arquivos JSON|*.json||"); if fp && File.exist?(fp); begin; imported = JSON.parse(File.read(fp), symbolize_names: true); if imported.is_a?(Hash) && [:types,:materials].all?{|k|imported.key?(k)}; self.property_manager.update_properties(imported); dialog.execute_script("populateData(#{self.property_manager.properties.to_json})"); UI.messagebox("Dados importados! Reinicie o SketchUp para atualizar toolbars."); else UI.messagebox("Erro: Estrutura JSON inválida."); end; rescue JSON::ParserError => e; UI.messagebox("Erro JSON: #{e.message}"); end; end; true }; dialog.add_action_callback("get_icons_list") { |_ctx| icons = get_generated_icons_list; dialog.execute_script("populateIconsList(#{icons.to_json})"); true }; dialog.add_action_callback("delete_icons") { |_ctx, icons_json| icons_arr = JSON.parse(icons_json); success = delete_generated_icons(icons_arr); dialog.execute_script("confirmIconsDeleted(#{success})"); true }; dialog.add_action_callback("get_sketchup_materials") do |_ctx|; materials = Sketchup.active_model.materials.map(&:name).uniq.sort; dialog.execute_script("populateSketchupMaterials(#{materials.to_json})"); true; end; dialog.show; end
      ICONS_SUBFOLDER = "material_config_icons"

      def self.get_icons_base_path
        File.join(Rjv::MockupTools::PLUGIN_ROOT_DIR, "icons", ICONS_SUBFOLDER)
      end

      def self.save_generated_icon(item_data, item_type_hint_ignored = nil)
        begin
          base_name = item_data[:name].to_s.gsub(/[^a-zA-Z0-9_.-]/,'_').gsub(/\s+/,'_')
          file_name = "#{base_name}.png"
          icons_path = get_icons_base_path
          Dir.mkdir(icons_path) unless Dir.exist?(icons_path)
          file_path = File.join(icons_path, file_name)
          data_part = item_data[:icon_data].split(',')[1]
          return false unless data_part
          File.open(file_path,"wb"){|f| f.write(Base64.decode64(data_part))}
          true
        rescue => e
          UI.messagebox("Erro salvar ícone '#{item_data[:name]}': #{e.message}")
          false
        end
      end

      def self.get_generated_icons_list
        path = get_icons_base_path
        return [] unless Dir.exist?(path)
        Dir.entries(path).select{|f| File.file?(File.join(path,f)) && f.downcase.end_with?('.png')}
      end

      def self.delete_generated_icons(icons_arr)
        path = get_icons_base_path
        return false unless Dir.exist?(path)
        deleted = 0
        icons_arr.each do |name|
          fp = File.join(path,name)
          if File.exist?(fp)
            begin
              File.delete(fp)
              deleted += 1
            rescue
            end
          end
        end
        if deleted > 0
          puts "#{deleted} ícone(s) excedente(s) excluído(s)."
        end
        return deleted > 0
      end

      def self.cleanup_invalid_icons
        path = get_icons_base_path
        return false unless Dir.exist?(path)

        cleaned = 0
        Dir.entries(path).each do |filename|
          next if filename == '.' || filename == '..'
          next unless filename.downcase.end_with?('.png')

          filepath = File.join(path, filename)
          begin
            # Verifica se arquivo é válido (tamanho > 0)
            if File.size(filepath) == 0
              File.delete(filepath)
              cleaned += 1
              puts "Removido ícone inválido: #{filename}"
            end
          rescue => e
            puts "Erro ao verificar #{filename}: #{e.message}"
          end
        end

        UI.messagebox("#{cleaned} ícone(s) inválido(s) removido(s).") if cleaned > 0
        return cleaned > 0
      end

      def self.generate_icon_path_for_toolbar(item_name)
        normalized = item_name.to_s.gsub(/[^a-zA-Z0-9_.-]/,'_').gsub(/\s+/,'_')
        File.join(get_icons_base_path, "#{normalized}.png")
      end
      
      # --- FUNÇÃO DE APLICAR MATERIAL ATUALIZADA ---
      def self.execute_material_action(material_props)
        model = Sketchup.active_model; selection = model.selection; targets = selection.select { |e| e.is_a?(Sketchup::ComponentInstance) }; if targets.empty?; UI.messagebox("Selecione um ou mais COMPONENTES para aplicar o material '#{material_props[:name]}'."); return; end; material_to_apply = nil; sketchup_material_name = material_props[:sketchupMaterial] || material_props['sketchupMaterial']; if sketchup_material_name && !sketchup_material_name.strip.empty?; material_to_apply = model.materials[sketchup_material_name]; unless material_to_apply; material_to_apply = model.materials.add(sketchup_material_name); color_prop_from_json = material_props[:color] || material_props['color']; if color_prop_from_json; begin; material_to_apply.color = Sketchup::Color.new(color_prop_from_json); rescue; end; end; end; end; model.start_operation("Aplicar Material MakettePro", true); thickness_cm_for_formula = material_props[:thickness].to_f; material_name_for_dc = material_props[:name].to_s; layer_name_for_dc = material_props[:layer].to_s; physical_thickness_mm_for_dc = thickness_cm_for_formula * 10.0; total_success_count = 0; total_error_count = 0; total_skipped_by_user = 0; layer_name_for_instance = material_props[:layer].to_s; material_name_for_instance_name = material_props[:name].to_s; color_prop = material_props[:color]; target_layer_obj = model.layers.add(layer_name_for_instance); target_layer_obj.color = Sketchup::Color.new(color_prop) if color_prop && color_prop != ""; processed_definitions_this_run = {}; targets_by_definition = targets.group_by(&:definition); targets_by_definition.each do |original_definition_key, instances_in_selection_of_this_def|; apply_to_all = false; make_selected_unique = false; if original_definition_key.instances.length > 1 && instances_in_selection_of_this_def.length < original_definition_key.instances.length; msg = "Definição '#{original_definition_key.name}' (#{original_definition_key.instances.length} insts).\nAplicar '#{material_name_for_dc}' a:\n[Sim] TODAS instâncias (altera definição)\n[Não] APENAS à(s) #{instances_in_selection_of_this_def.length} selecionada(s) (torna única(s))"; result = UI.messagebox(msg, MB_YESNOCANCEL); if result == IDYES; apply_to_all = true; elsif result == IDNO; make_selected_unique = true; else total_skipped_by_user += instances_in_selection_of_this_def.length; next; end; else; apply_to_all = true; end; definitions_to_process_this_iteration = []; if apply_to_all; definitions_to_process_this_iteration << original_definition_key; elsif make_selected_unique; instances_in_selection_of_this_def.each do |inst|; inst.make_unique if inst.definition.instances.length > 1; definitions_to_process_this_iteration << inst.definition unless definitions_to_process_this_iteration.include?(inst.definition); end; end; definitions_to_process_this_iteration.each do |current_definition_to_modify|; def_id = current_definition_to_modify.entityID; unless processed_definitions_this_run.key?(def_id); current_definition_to_modify.set_attribute("MakettePro", "identifier", "MakettePro"); bake_success = bake_scale_into_definition_and_reset_instances(current_definition_to_modify, thickness_cm_for_formula, layer_name_for_dc, material_name_for_dc, physical_thickness_mm_for_dc); processed_definitions_this_run[def_id] = bake_success; end; instances_of_current_def = if apply_to_all && current_definition_to_modify == original_definition_key; original_definition_key.instances.to_a; elsif make_selected_unique; instances_in_selection_of_this_def.select { |sel_inst| sel_inst.definition == current_definition_to_modify }; else; []; end; instances_of_current_def.each do |inst|; if processed_definitions_this_run[def_id]; inst.layer = target_layer_obj; inst.name = material_name_for_instance_name; inst.material = material_to_apply; if targets.include?(inst) && !(@counted_success_insts&.include?(inst.entityID)); total_success_count += 1; @counted_success_insts ||= []; @counted_success_insts << inst.entityID; end; else; if targets.include?(inst) && !(@counted_error_insts&.include?(inst.entityID)); total_error_count += 1; @counted_error_insts ||= []; @counted_error_insts << inst.entityID; end; end; end; end; end; @counted_success_insts = nil; @counted_error_insts = nil; model.commit_operation
        message = "#{total_success_count} aplic. de '#{material_name_for_dc}' ok."
        message += " #{total_skipped_by_user} pulado(s), #{total_error_count} falha(s)." if total_skipped_by_user > 0 || total_error_count > 0
        Sketchup.status_text = message
        puts message
      end
      
      private_class_method def self.bake_scale_into_definition_and_reset_instances(definition_to_process, thickness_cm_for_formula, layer_name_for_dc, material_name_for_dc, physical_thickness_mm_for_dc)
  begin
    physical_thickness_mm = thickness_cm_for_formula * 10.0
    definition_to_process.invalidate_bounds
    current_def_z_depth_inches = definition_to_process.bounds.depth.to_l
    target_def_z_depth_inches = physical_thickness_mm.mm.to_l
    
    scale_factor_for_def_z = 1.0
    if current_def_z_depth_inches > TOLERANCE && target_def_z_depth_inches > TOLERANCE
      scale_factor_for_def_z = target_def_z_depth_inches / current_def_z_depth_inches
    end
    
    # Aplicar escala na definição se necessário
    if (scale_factor_for_def_z - 1.0).abs > TOLERANCE && current_def_z_depth_inches > TOLERANCE && definition_to_process.entities.count > 0
      begin
        entities_to_transform = definition_to_process.entities.to_a
        if entities_to_transform.any?
          # Transformação de escala somente no eixo Z
          scale_transform = Geom::Transformation.scaling(Geom::Point3d.new(0,0,0), 1.0, 1.0, scale_factor_for_def_z)
          definition_to_process.entities.transform_entities(scale_transform, entities_to_transform)
          definition_to_process.invalidate_bounds
        end
      rescue => e
        puts "Erro ao escalar entidades na definição '#{definition_to_process.name}': #{e.message}"
        return false
      end
    end
    
    # Configurar atributos dinâmicos
    dc_dict = definition_to_process.attribute_dictionary("dynamic_attributes", true)
    dc_dict["_lengthunits"] = "CENTIMETERS"
    dc_dict["_lenz_formula"] = thickness_cm_for_formula.to_f.to_s
    dc_dict["scaletool"] = "All scale handles hidden."
    dc_dict["_layer"] = layer_name_for_dc
    dc_dict["_material"] = material_name_for_dc
    dc_dict["_thickness_mm"] = physical_thickness_mm_for_dc
    
    # Limpar cache de atributos dinâmicos
    if defined?($dc_observers) && $dc_observers
      begin
        definition_to_process.attribute_dictionaries.delete("cache-_lengthx-_lengthy-_lengthz") if definition_to_process.attribute_dictionaries
        definition_to_process.set_attribute("dynamic_attributes", "_refresh_material_time", Time.now.to_f)
      rescue => e
        puts "Aviso: Erro ao limpar cache de atributos dinâmicos: #{e.message}"
      end
    end
    
    # Corrigir transformações das instâncias (baseado no código do Thomas)
    if (scale_factor_for_def_z - 1.0).abs > TOLERANCE
      tr_correction = Geom::Transformation.scaling(1.0, 1.0, 1.0 / scale_factor_for_def_z)
      
      definition_to_process.instances.each do |instance|
        begin
          # Aplicar correção baseada na lógica do Thomas Thomassen
          tr_current = instance.transformation
          # A correção deve ser: transformação_atual * correção * inversa_da_transformação_atual
          corrected_transform = tr_current * tr_correction * tr_current.inverse
          instance.transform!(corrected_transform)
          
          # Forçar atualização dos dynamic components se disponível
          if defined?($dc_observers) && $dc_observers
            begin
              $dc_observers.get_latest_class.redraw_with_undo(instance)
            rescue => e
              puts "Aviso: Erro ao atualizar dynamic component: #{e.message}"
            end
          end
        rescue => e
          puts "Erro ao corrigir transformação da instância #{instance.entityID}: #{e.message}"
          puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
        end
      end
    else
      # Mesmo sem escala, atualizar dynamic components se necessário
      definition_to_process.instances.each do |instance|
        if defined?($dc_observers) && $dc_observers
          begin
            $dc_observers.get_latest_class.redraw_with_undo(instance)
          rescue => e
            puts "Aviso: Erro ao atualizar dynamic component: #{e.message}"
          end
        end
      end
    end
    
    return true
    
  rescue => e
    puts "Erro crítico em bake_scale_into_definition_and_reset_instances para '#{definition_to_process.name}': #{e.message}"
    puts "Backtrace: #{e.backtrace.first(5).join("\n")}"
    return false
  end
end
      
      module ToolbarMaterial; extend self; def self.create_material_toolbar; return if @toolbar_instance_material; materials_all = Rjv::MockupTools::MaterialSystem.property_manager.properties[:materials] || []; active_materials = materials_all.select { |m| m[:active] }; toolbar_name = "RJV Materiais"; return if active_materials.empty?; @toolbar_instance_material = UI::Toolbar.new(toolbar_name); grouped_materials = active_materials.group_by { |m| m[:type] }; sorted_types = grouped_materials.keys.sort; sorted_types.each_with_index do |type, type_idx|; materials_of_type = grouped_materials[type].sort_by { |m| m[:name].to_s }; materials_of_type.each do |material|; cmd = UI::Command.new(material[:name].to_s) { Rjv::MockupTools::MaterialSystem.execute_material_action(material) }; cmd.tooltip = "#{material[:name]}"; icon_path = Rjv::MockupTools::MaterialSystem.generate_icon_path_for_toolbar(material[:name]); cmd.small_icon = icon_path; cmd.large_icon = icon_path; @toolbar_instance_material.add_item(cmd); end; if type_idx < sorted_types.length - 1 && materials_of_type.any? && sorted_types[type_idx+1] && grouped_materials[sorted_types[type_idx+1]]&.any?; @toolbar_instance_material.add_separator; end; end; @toolbar_instance_material.show if @toolbar_instance_material.count > 0; end; end

      def self.initialize_material_system; self.property_manager; end
	  def self.get_grouped_materials_for_selector
        all_materials = self.property_manager.properties[:materials] || []
        all_types = self.property_manager.properties[:types] || []
        
        # Cria um mapa de tipos para cores para referência rápida
        type_colors = all_types.map { |type| [type[:name], type[:color]] }.to_h
        
        active_materials = all_materials.select { |m| m[:active] }
        grouped = {}
        
        active_materials.each do |material|
          # 1. Usa o campo 'type' como a chave principal. É a fonte da verdade.
          base_name = material[:type]
          next unless base_name # Pula se o material não tiver um tipo definido
          
          # 2. Tenta extrair a espessura do campo 'name' para o texto do botão
          thickness_name = material[:name].to_s.gsub(base_name, '').strip
          # Se não conseguir extrair, usa um fallback
          thickness_name = "#{material[:thickness] * 10}mm" if thickness_name.empty?

          # 3. Agrupa os dados
          # Se o grupo ainda não existe, inicializa com a cor do TIPO, não do material.
          grouped[base_name] ||= { color: type_colors[base_name] || material[:color], thicknesses: [] }
          
          grouped[base_name][:thicknesses] << { 
            name: thickness_name, 
            full_name: material[:name] 
          }
        end
        
        # Ordena as espessuras numericamente dentro de cada grupo
        grouped.each do |_, data|
          data[:thicknesses].sort_by! { |t| t[:name].to_f }
        end

        return grouped
      end
    end
  end
end