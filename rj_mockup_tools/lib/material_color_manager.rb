# encoding: UTF-8
require 'sketchup.rb'
require 'json'

require_relative 'deep_paint_tool.rb'

module Rjv
  module MockupTools
    module MaterialColorManager
      extend self
      SUFFIX = " (Alternativo)".freeze
      PALETTE_COMPONENT_NAME = "RJV_PaletaDeMateriais".freeze
      @dialog = nil

      def open_dialog
        if @dialog && @dialog.visible?; @dialog.bring_to_front; return; end
        
        ensure_alternative_materials_exist
        
        dialog_style = UI::HtmlDialog::STYLE_DIALOG
        if Sketchup.version.to_i >= 17; begin; dialog_style = UI::HtmlDialog::STYLE_PALETTE; rescue; end; end
        
        dialog_options = { dialog_title: "Gerenciador de Cores", width: 420, height: 550, style: dialog_style }
        @dialog = UI::HtmlDialog.new(dialog_options)
        html_path = File.join(Rjv::MockupTools::PLUGIN_ROOT_DIR, 'html', 'color_manager_dialog.html')
        @dialog.set_file(html_path)

        # Callbacks
        @dialog.add_action_callback("load_initial_data") { |_, _| update_dialog_data }
        @dialog.add_action_callback("toggle_colors") { |_, _| swap_colors }
        @dialog.add_action_callback("create_palette") { |_, _| create_or_update_palette }
        @dialog.add_action_callback("update_material_color") { |_, name, color| update_material_color(name, color) }
        @dialog.add_action_callback("rename_material") { |_, old, new| rename_material_pair(old, new) }
        @dialog.add_action_callback("activate_deep_paint_tool") { |_, mat_name| activate_deep_paint_tool(mat_name) }

        @dialog.set_on_closed { @dialog = nil }
        @dialog.show
      end

      def activate_deep_paint_tool(material_name)
        model = Sketchup.active_model; material = model.materials[material_name]
        if material; model.tools.push_tool(DeepPaintTool.new(material)); else; UI.messagebox("Material '#{material_name}' não encontrado."); end
      end

      private
      
      # --- CORREÇÃO CRÍTICA DO BUGSPLAT ---
      def ensure_alternative_materials_exist
        model = Sketchup.active_model
        
        # 1. Crie uma cópia estática da lista de materiais com .to_a
        #    Isso nos permite iterar sobre a cópia enquanto modificamos o original.
        materials_to_check = model.materials.to_a
        
        materials_to_add = []

        # 2. Primeira passagem: APENAS COLETE informações.
        materials_to_check.each do |mat|
          next if mat.texture || mat.name.start_with?('_') || mat.name.end_with?(SUFFIX)
          alt_name = "#{mat.name}#{SUFFIX}"
          # Se o material alternativo não existe, guarde o nome para criar depois.
          unless model.materials[alt_name]
            materials_to_add << alt_name
          end
        end

        # 3. Segunda passagem: Se houver algo para criar, AJA AGORA.
        #    Isso só acontece se a lista não estiver vazia.
        unless materials_to_add.empty?
          model.start_operation("Criar Materiais Alternativos", true)
          materials_to_add.each do |name|
            model.materials.add(name).color = "#CCCCCC"
          end
          model.commit_operation
        end
      end
      
      def update_dialog_data
        return unless @dialog&.visible?
        @dialog.execute_script("populateMaterials(#{get_materials_data.to_json})")
      end

      def get_materials_data
        model = Sketchup.active_model; materials_data = []
        model.materials.to_a.sort_by(&:name).each do |mat|
          next if mat.texture || mat.name.start_with?('_') || mat.name.end_with?(SUFFIX)
          alt_mat = model.materials["#{mat.name}#{SUFFIX}"]
          next unless alt_mat 
          materials_data << {
            name: mat.name,
            color_a: "##{"%02x" % mat.color.red}#{"%02x" % mat.color.green}#{"%02x" % mat.color.blue}",
            color_b: "##{"%02x" % alt_mat.color.red}#{"%02x" % alt_mat.color.green}#{"%02x" % alt_mat.color.blue}"
          }
        end
        return materials_data
      end

      def update_material_color(material_name, hex_color)
        material = Sketchup.active_model.materials[material_name]
        if material; begin; material.color = Sketchup::Color.new(hex_color); rescue; end; end
      end

      def swap_colors
        model = Sketchup.active_model
        model.start_operation("Alternar Cores", true)
        materials_to_swap = get_materials_data
        materials_to_swap.each do |mat_data|
          original_mat = model.materials[mat_data[:name]]
          alt_mat = model.materials["#{mat_data[:name]}#{SUFFIX}"]
          next unless original_mat && alt_mat
          original_color = original_mat.color
          original_mat.color = alt_mat.color
          alt_mat.color = original_color
        end
        model.commit_operation
        update_dialog_data
      end
      
      def rename_material_pair(old_name, new_name)
        model = Sketchup.active_model
        if new_name.empty? || model.materials[new_name] || model.materials["#{new_name}#{SUFFIX}"]
          UI.messagebox("O nome '#{new_name}' é inválido ou já está em uso."); update_dialog_data; return
        end
        model.start_operation("Renomear Par de Materiais", true)
        original_mat = model.materials[old_name]; alt_mat = model.materials["#{old_name}#{SUFFIX}"]
        original_mat.name = new_name if original_mat
        alt_mat.name = "#{new_name}#{SUFFIX}" if alt_mat
        model.commit_operation
        update_dialog_data
      end
      
      def create_or_update_palette
        model = Sketchup.active_model
        definitions = model.definitions
        model.start_operation("Criar/Atualizar Paleta", true)
        if existing_def = definitions[PALETTE_COMPONENT_NAME]
          existing_def.instances.map(&:erase!)
        end
        mats_to_display = []
        get_materials_data.each do |data|
          mats_to_display << model.materials[data[:name]]
          mats_to_display << model.materials["#{data[:name]}#{SUFFIX}"]
        end
        mats_to_display.compact!
        if mats_to_display.empty?
          model.abort_operation
          UI.messagebox("Nenhum material para exibir na paleta.")
          return
        end
        palette_def = definitions.add(PALETTE_COMPONENT_NAME)
        ents = palette_def.entities
        square_size = 50.mm; spacing = 10.mm
        count = mats_to_display.length
        cols = Math.sqrt(count).ceil
        mats_to_display.each_with_index do |mat, i|
          row = i / cols; col = i % cols
          x = col * (square_size + spacing)
          y = row * (square_size + spacing)
          pts = [[x, y, 0], [x + square_size, y, 0], [x + square_size, y + square_size, 0], [x, y + square_size, 0]]
          face = ents.add_face(pts)
          face.material = mat
        end
        start_point = Geom::Point3d.new(50.mm, -1000.mm, 0)
        transformation = Geom::Transformation.new(start_point)
        instance = model.entities.add_instance(palette_def, transformation)
        instance.locked = true
        definitions.purge_unused
        model.commit_operation
        Sketchup.status_text = "Paleta de materiais criada/atualizada com sucesso."
      end
    end
  end
end