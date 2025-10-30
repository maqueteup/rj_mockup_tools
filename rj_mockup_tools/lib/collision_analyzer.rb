# encoding: UTF-8
require 'json'

module Rjv
  module MockupTools
    module CollisionAnalyzer
      extend self
      @dialog = nil
      FOCUS_GROUP_NAME = "[RJV] Foco de Colisões".freeze
      
      @world_transform_cache = {}

      def open_dialog
        if @dialog && @dialog.visible?; @dialog.bring_to_front; return; end
        dialog_style = UI::HtmlDialog::STYLE_DIALOG
        if Sketchup.version.to_i >= 17; begin; dialog_style = UI::HtmlDialog::STYLE_PALETTE; rescue NameError; end; end
        
        dialog = @dialog = UI::HtmlDialog.new({
          dialog_title: "Analisador de Colisões",
          width: 550, height: 700,
          style: dialog_style
        })
        
        html_file = File.join(Rjv::MockupTools::PLUGIN_ROOT_DIR, "html", "collision_analyzer.html")
        dialog.set_file(html_file)
        
        dialog.add_action_callback("start_analysis") do |action_context, in_focus_group|
          suspect_pairs, components_count = find_suspects_and_prepare_cache(in_focus_group: in_focus_group)
          dialog.execute_script("window.analyzerUI.startVerificationProcess(#{suspect_pairs.to_json}, #{components_count})")
        end
        
        dialog.add_action_callback("verify_single_pair") do |action_context, pair|
          is_colliding = verify_narrow_phase(pair['pid1'], pair['pid2'])
          dialog.execute_script("window.analyzerUI.handleVerificationResult(#{pair.to_json}, #{is_colliding})")
        end
        
        dialog.add_action_callback("select_instances") { |_, pids| select_instances(pids) }
        dialog.add_action_callback("enter_focus_mode") { |_, pids| enter_focus_mode(pids) }
        dialog.add_action_callback("exit_focus_mode") { |_, _| exit_focus_mode }

        # [A MUDANÇA ESTÁ AQUI]
        # Agora, ao fechar o diálogo, a função para limpar o grupo de foco é chamada.
        dialog.set_on_closed do
          exit_focus_mode
          @dialog = nil
        end
        
        dialog.show
      end

      private
      
      def find_suspects_and_prepare_cache(in_focus_group: false)
        model = Sketchup.active_model
        @world_transform_cache.clear
        
        scope = if in_focus_group
                  focus_group = model.entities.grep(Sketchup::Group).find { |g| g.name == FOCUS_GROUP_NAME }
                  focus_group ? focus_group.entities : []
                else
                  model.selection.empty? ? model.active_entities : model.selection
                end
        
        instances_data = find_makette_pro_components_recursive(scope)
        instances_data.each { |data| @world_transform_cache[data[:instance].persistent_id] = data[:transformation] }

        return [[], instances_data.length] if instances_data.length < 2

        suspect_pairs = []
        instances_data.combination(2) do |data1, data2|
          bb1_world = transform_bounding_box(data1[:instance].definition.bounds, data1[:transformation])
          bb2_world = transform_bounding_box(data2[:instance].definition.bounds, data2[:transformation])
          
          if bb1_world.intersect(bb2_world).valid?
            inst1 = data1[:instance]
            inst2 = data2[:instance]

            # [MUDANÇA] - Prepara os nomes. Usa o nome da instância, se existir.
            instance_name1 = inst1.name.empty? ? inst1.definition.name : inst1.name
            instance_name2 = inst2.name.empty? ? inst2.definition.name : inst2.name

            suspect_pairs << {
              pid1: inst1.persistent_id,
              definitionName1: inst1.definition.name, # Nome da definição para o tooltip
              instanceName1: instance_name1,           # Nome da instância para exibição principal
              
              pid2: inst2.persistent_id,
              definitionName2: inst2.definition.name, # Nome da definição para o tooltip
              instanceName2: instance_name2            # Nome da instância para exibição principal
            }
          end
        end
        
        return [suspect_pairs, instances_data.length]
      end

      def verify_narrow_phase(pid1, pid2)
        model = Sketchup.active_model
        instance1 = model.find_entity_by_persistent_id(pid1)
        instance2 = model.find_entity_by_persistent_id(pid2)
        transform1 = @world_transform_cache[pid1]
        transform2 = @world_transform_cache[pid2]
        return false unless instance1 && instance2 && transform1 && transform2
        return solids_intersect?(instance1, transform1, instance2, transform2)
      end

      def transform_bounding_box(local_bb, world_transform)
        world_bb = Geom::BoundingBox.new
        (0..7).each { |i| world_bb.add(local_bb.corner(i).transform(world_transform)) }
        world_bb
      end
      
      def solids_intersect?(instance1, transform1, instance2, transform2)
        model = Sketchup.active_model
        model.start_operation("CollisionTest", true, false, true)
        collision_found = false
        temp_entities_to_erase = []
        begin
          ents = model.active_entities
          temp_group1 = create_merged_solid_group(ents, instance1, transform1)
          temp_group2 = create_merged_solid_group(ents, instance2, transform2)
          temp_entities_to_erase.concat([temp_group1, temp_group2].compact)
          if temp_group1 && temp_group2
            result_group = temp_group1.intersect(temp_group2)
            temp_entities_to_erase << result_group if result_group.is_a?(Sketchup::Entity)
            
            # --- A CORREÇÃO ESTÁ AQUI ---
            # Trocamos !.empty? por .length > 0
            collision_found = result_group.is_a?(Sketchup::Group) && result_group.entities.length > 0
          end
        rescue => e
          puts "Aviso: A verificação booleana falhou para um par. #{e.message}"
        ensure
          ents.erase_entities(temp_entities_to_erase.select(&:valid?))
          model.commit_operation
        end
        collision_found
      end
      
      def create_merged_solid_group(entities_context, instance, transform)
        novo_grupo = entities_context.add_group
        faces_para_copiar = instance.definition.entities.grep(Sketchup::Face)
        return nil if faces_para_copiar.empty?
        faces_para_copiar.each do |face|
          new_face = novo_grupo.entities.add_face(face.outer_loop.vertices.map(&:position))
          if face.loops.length > 1
            face.loops.drop(1).each do |loop|
              hole_face = novo_grupo.entities.add_face(loop.vertices.map(&:position))
              hole_face.erase! if hole_face.valid?
            end
          end
        end
        edges_to_erase = novo_grupo.entities.grep(Sketchup::Edge).select { |e| e.faces.length == 2 && e.faces[0].normal.parallel?(e.faces[1].normal) }
        novo_grupo.entities.erase_entities(edges_to_erase) if edges_to_erase.any?
        novo_grupo.transformation = transform
        novo_grupo
      end
      
      def enter_focus_mode(pids)
        model = Sketchup.active_model; exit_focus_mode
        all_instances_data = find_makette_pro_components_recursive(model.active_entities)
        instances_data_to_copy = all_instances_data.select { |data| pids.include?(data[:instance].persistent_id) }
        return if instances_data_to_copy.empty?
        model.start_operation("Isolar Colisões", true)
        focus_group = model.entities.add_group; focus_group.name = FOCUS_GROUP_NAME
        instances_data_to_copy.each { |data| focus_group.entities.add_instance(data[:instance].definition, data[:transformation]) }
        move_vector = focus_group.bounds.center.vector_to(ORIGIN)
        focus_group.transform!(Geom::Transformation.translation(move_vector))
        model.active_view.zoom(focus_group)
        model.selection.clear; model.selection.add(focus_group)
        model.commit_operation
        @dialog.execute_script("window.analyzerUI.setFocusMode(true)") if @dialog
      end

      def exit_focus_mode
        model = Sketchup.active_model
        model.close_active if model.active_path && !model.active_path.empty?
        model.start_operation("Sair do Modo de Foco", true)
        focus_group = model.entities.grep(Sketchup::Group).find { |g| g.name == FOCUS_GROUP_NAME }
        focus_group.erase! if focus_group && focus_group.valid?
        model.selection.clear
        model.commit_operation
        @dialog.execute_script("window.analyzerUI.setFocusMode(false)") if @dialog
      end
      
      def find_makette_pro_components_recursive(entities, result_array = [], transformation = Geom::Transformation.new)
        entities.each do |entity|
          if (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) && entity.valid?
            world_transformation = transformation * entity.transformation
            definition = entity.definition rescue entity
            if definition.get_attribute("MakettePro", "identifier") == "MakettePro"
              result_array << { instance: entity, transformation: world_transformation }
            end
            definition_entities = entity.definition.entities rescue entity.entities
            find_makette_pro_components_recursive(definition_entities, result_array, world_transformation) if definition_entities
          end
        end
        result_array.uniq { |data| data[:instance].persistent_id }
      end
      
      def select_instances(pids)
        model = Sketchup.active_model; model.selection.clear
        entities = pids.map { |pid| model.find_entity_by_persistent_id(pid) }.compact
        model.selection.add(entities)
      end
    end
  end
end