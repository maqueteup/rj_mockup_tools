# encoding: UTF-8
require 'sketchup.rb'
require 'json' 

module Rjv
  module MockupTools
    module StampName
      extend self
      
      STAMP_LAYER_NAME = "MU_Texto".freeze
      STAMP_ATTRIBUTE_DICT = "Rjv_StampName".freeze
      STAMP_GROUP_IDENTIFIER_KEY = "IsStampNameGroup".freeze
      # --- NOVA CHAVE DE ATRIBUTO ---
      PARENT_DEF_NAME_KEY = "ParentDefName".freeze # Para "lembrar" o nome do pai
      
      Z_AXIS_GLOBAL = Geom::Vector3d.new(0, 0, 1).freeze; TOLERANCE = 1e-4

      def self.load_settings
        Rjv::MockupTools::StampConfigManager.load_settings
      end
      
      def self.save_settings(settings_hash)
        Rjv::MockupTools::StampConfigManager.save_settings(settings_hash)
      end

      def self.configure_stamp_settings
        current = load_settings
        font_list = ["TXT", "Simplex", "1CamBam_Stick_1"]
        unless font_list.include?(current[:fontName]); font_list.unshift(current[:fontName]); end
        font_list_str = font_list.join("|")

        # ✅ LISTA DE CANTOS
        corner_options = {
          "bottom_left" => "Inferior Esquerdo",
          "bottom_right" => "Inferior Direito",
          "top_left" => "Superior Esquerdo",
          "top_right" => "Superior Direito"
        }
        current_corner = current[:corner] || "bottom_left"
        corner_list_str = corner_options.values.join("|")
        current_corner_label = corner_options[current_corner] || "Inferior Esquerdo"

        prompts = ["Fonte:", "Tamanho (mm):", "Offset X (mm):", "Offset Y (mm):", "Canto:"]
        defaults = [current[:fontName], current[:fontSize], current[:offsetX], current[:offsetY], current_corner_label]
        lists = [font_list_str, "", "", "", corner_list_str]
        results = UI.inputbox(prompts, defaults, lists, "Configurações do Carimbo (Texto 3D)")
        return unless results

        # Converte label de volta para key
        selected_corner = corner_options.key(results[4]) || "bottom_left"

        save_settings({
          fontName: results[0],
          fontSize: results[1].to_f,
          offsetX: results[2].to_f,
          offsetY: results[3].to_f,
          corner: selected_corner
        })
        UI.messagebox("Configurações salvas!")
      end
      
      def self.run
        model = Sketchup.active_model; selection = model.selection
        if selection.empty?; UI.messagebox("Selecione um ou mais Componentes."); return; end
        settings = load_settings
        stamp_layer = model.layers.add(STAMP_LAYER_NAME)
		stamp_layer.color = [0, 255, 0] if stamp_layer
        return unless stamp_layer
        model.start_operation("Aplicar Carimbo (Texto 3D)", true)
        @processed_definitions = {}; @applied_count = 0; @skipped_count = 0
        selection.each { |entity| apply_stamp_recursively(entity, settings, stamp_layer) }
        model.commit_operation
        message = "#{@applied_count} carimbo(s) aplicado(s). #{@skipped_count} ignorado(s)."
        Sketchup.status_text = message; puts message
      end

      private

      def apply_stamp_recursively(entity, settings, stamp_layer)
        if entity.is_a?(Sketchup::ComponentInstance)
          definition = entity.definition
          return if @processed_definitions[definition.guid]
          if definition.get_attribute("MakettePro", "identifier") == "MakettePro"
            @processed_definitions[definition.guid] = true
            target_entities = definition.entities
            already_stamped = target_entities.any? { |e| e.layer == stamp_layer }
            if already_stamped
              @skipped_count += 1
            else
              top_face = find_top_face(target_entities)
              if top_face
                # Passa a definição do componente pai para a função de criação
                create_stamp_as_group(definition, top_face, settings, stamp_layer)
                @applied_count += 1
              end
            end
          end
        end
        if entity.respond_to?(:definition) && entity.definition
          entities_to_search = entity.definition.entities
          entities_to_search.each { |child| apply_stamp_recursively(child, settings, stamp_layer) }
        end
      end

      # --- FUNÇÃO DE CRIAÇÃO ATUALIZADA ---
      def create_stamp_as_group(parent_definition, top_face, settings, stamp_layer)
        stamp_text = parent_definition.name.empty? ? "SemNome" : parent_definition.name
        target_entities = parent_definition.entities

        face_bounds = top_face.bounds

        # ✅ CRIA TEXTO TEMPORÁRIO PARA OBTER SUA BOUNDING BOX
        temp_group = target_entities.add_group
        temp_group.entities.add_3d_text(
          stamp_text, TextAlignLeft, settings[:fontName],
          false, false, settings[:fontSize].mm, 0.0, 0.0, false, 0.0
        )
        text_bounds = temp_group.bounds

        # ✅ CALCULA PONTO BASE CONFORME O CANTO ESCOLHIDO (USANDO FACE BOUNDS)
        corner = settings[:corner] || "bottom_left"
        base_pt = case corner
                  when "bottom_left"
                    face_bounds.min
                  when "bottom_right"
                    Geom::Point3d.new(face_bounds.max.x, face_bounds.min.y, face_bounds.min.z)
                  when "top_left"
                    Geom::Point3d.new(face_bounds.min.x, face_bounds.max.y, face_bounds.min.z)
                  when "top_right"
                    Geom::Point3d.new(face_bounds.max.x, face_bounds.max.y, face_bounds.min.z)
                  else
                    face_bounds.min
                  end

        base_pt_on_plane = base_pt.project_to_plane(top_face.plane)

        # ✅ AJUSTA OFFSET BASEADO NO CANTO E BOUNDING BOX DO TEXTO
        offset_x = settings[:offsetX].mm
        offset_y = settings[:offsetY].mm

        # Para cantos à direita, subtrai a largura do texto do offset
        if corner.include?("right")
          offset_x = -offset_x - text_bounds.width
        end

        # Para cantos superiores, subtrai a altura do texto do offset
        if corner.include?("top")
          offset_y = -offset_y - text_bounds.height
        end

        offset_vector = Geom::Vector3d.new(offset_x, offset_y, 0)
        insertion_point = base_pt_on_plane.offset(offset_vector)

        # ✅ MOVE O GRUPO TEMPORÁRIO PARA A POSIÇÃO FINAL
        transform = Geom::Transformation.translation(insertion_point)
        temp_group.transform!(transform)

        # Renomeia e configura o grupo
        temp_group.name = "RJVStamp_#{stamp_text.gsub(/[^\w_.-]/, '_').slice(0,30)}"
        temp_group.layer = stamp_layer
        temp_group.set_attribute(STAMP_ATTRIBUTE_DICT, STAMP_GROUP_IDENTIFIER_KEY, true)
        temp_group.set_attribute(STAMP_ATTRIBUTE_DICT, PARENT_DEF_NAME_KEY, parent_definition.name)
        
        return true
      end

      def find_top_face(ents); tf=nil; mz=-1.0/0.0; ents.grep(Sketchup::Face).each{|f| next unless f.valid?; begin;n=f.normal;next unless n.parallel?(Z_AXIS_GLOBAL,TOLERANCE)&&n.z>0;cz=f.bounds.center.z;if cz>mz;mz=cz;tf=f;end;rescue;next;end}; if tf.nil?;pf=ents.grep(Sketchup::Face).select(&:valid?);tf=pf.max_by{|f|f.bounds.center.z rescue -1.0/0.0};end;return tf;end
    
    end 
  end 
end