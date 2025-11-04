# encoding: UTF-8
# Mockup Tools RJV - Face to Board Tool Module

require 'sketchup.rb'

module Rjv
  module MockupTools
    module FaceToBoard # Specific module for this tool

      # --- Tool Constants ---
      DEFAULT_THICKNESS_MM = 2.0
      Z_AXIS = Geom::Vector3d.new(0, 0, 1)
      TOLERANCE = 1e-4

      # --- Tool State ---
      @last_thickness_mm = DEFAULT_THICKNESS_MM

      # --- Main method called by the toolbar command ---
      def self.run
        model = Sketchup.active_model
        selection = model.selection
        selected_faces = selection.grep(Sketchup::Face).select(&:valid?)

        if selected_faces.empty?
          UI.messagebox("Nenhuma face válida selecionada para 'Face to Board'.", MB_OK, "Seleção Vazia")
          return
        end

        # Get thickness input
        prompts = ["Espessura da Placa (mm):"]
        defaults = [@last_thickness_mm.to_s]
        input = UI.inputbox(prompts, defaults, "Mockup Tools - Face to Board")
        return unless input # User cancelled

        begin
          thickness_mm = input[0].to_f
          if thickness_mm <= TOLERANCE; UI.messagebox("A espessura deve ser positiva."); return; end
          @last_thickness_mm = thickness_mm
          thickness_inches = thickness_mm.mm
        rescue ArgumentError; UI.messagebox("Valor inválido."); return; end

        model.start_operation("Face to Board", true)
        created_components = []
        failed_faces_info = {}
        faces_to_process = selected_faces.to_a

        faces_to_process.each do |face|
          unless face.valid?; puts "Aviso: Pulando face #{face.entityID} inválida."; next; end
          face_id_for_error = face.entityID
          # <<<< GUARDA O CONTEXTO ONDE A INSTÂNCIA SERÁ CRIADA >>>>
          # O novo componente será adicionado no mesmo container que a face original estava
          target_entities = face.parent.entities

          begin
            # Call the geometry creation method
            new_instance = create_component_geometry(face, thickness_inches, model)

            if new_instance && new_instance.valid?
              created_components << new_instance
              # Clean up original geometry
              begin
                if face.valid? && !face.deleted?
                  edges_to_delete = face.edges.select { |e| e.valid? && e.faces.length == 1 }
                  entities_to_erase = [face] + edges_to_delete
                  # <<<< APAGA DO CONTEXTO CORRETO >>>>
                  target_entities.erase_entities(entities_to_erase.select(&:valid?))
                end
              rescue => erase_error
                puts "Aviso: Erro ao apagar originais de #{face_id_for_error}: #{erase_error.message}"
              end
            else
              failed_faces_info[face_id_for_error] ||= "Falha na criação (ver console)."
            end
          rescue => e
            puts "Erro inesperado (Face ID #{face_id_for_error}): #{e.message}\n#{e.backtrace.first(3).join("\n")}"
            failed_faces_info[face_id_for_error] = "Erro inesperado: #{e.message}"
          end
        end # End faces loop

        model.commit_operation

        # --- User Feedback ---
        failed_count = failed_faces_info.keys.length
        success_count = created_components.length
        if success_count > 0
          model.selection.clear
          # <<<< SELECIONA NO CONTEXTO CORRETO? >>>>
          # Selecionar pode ser complicado se foi dentro de grupo.
          # Melhor apenas mostrar mensagem por enquanto.
          # model.selection.add(created_components) if created_components.any?
          message = "#{success_count} placa(s) criada(s)."
          if failed_count > 0
            message += "\nFalha em #{failed_count} face(s)."
            UI.messagebox(message)
            puts "Falha em faces IDs: #{failed_faces_info.keys.join(', ')}"
          else
             Sketchup.status_text = message
          end
        elsif failed_count > 0
          UI.messagebox("Falha ao processar #{failed_count} face(s) selecionada(s).\nVerifique o console Ruby.")
          puts "Falha em faces IDs: #{failed_faces_info.keys.join(', ')}"
        end
      end # End self.run

      # --- Helper method to get full transformation from nested contexts ---
      private_class_method def self.get_full_transformation(entity)
        transformation = Geom::Transformation.new # Start with identity
        current = entity.parent
        while current.respond_to?(:transformation) && !current.is_a?(Sketchup::Model)
           # Combine parent's transformation (pre-multiply)
           transformation = current.transformation * transformation
           # Move up the hierarchy
           # Se o parent for uma Definition, pegamos uma instância dela para continuar subindo
           if current.is_a?(Sketchup::ComponentDefinition)
              # Isso pode ser ambíguo se a definição tiver múltiplas instâncias
              # Vamos pegar a primeira instância encontrada no modelo ativo para subir
              instance_parent = current.instances.first
              current = instance_parent ? instance_parent.parent : Sketchup.active_model # Se não achar instância, para no modelo
           else
              # Se for Group ou ComponentInstance, apenas pega o parent
              current = current.parent
           end

        end
        transformation
      end


      # --- Private helper method for geometry creation ---
      private_class_method def self.create_component_geometry(original_face, thickness_inches, model)
        comp_def = nil
        begin
          # 1. Validations
          unless original_face.valid? && !original_face.deleted?
            raise "Erro Precoce: Face original inválida (ID: #{original_face.entityID})."
          end

          # 2. Get Data & Transforms
          # <<<< CORREÇÃO: Usa a função auxiliar para transformação completa >>>>
          full_parent_transformation = get_full_transformation(original_face)

          # Calcula vértices e normal no espaço do MODELO (World Coordinates)
          outer_loop_world_verts = original_face.outer_loop.vertices.map { |v| v.position.transform(full_parent_transformation) }
          inner_loops_world_verts = original_face.loops.select { |l| !l.outer? }.map do |loop|
            loop.vertices.map { |v| v.position.transform(full_parent_transformation) }
          end
          # Normal já está no sistema local da face, transforma para mundo
          world_normal = original_face.normal.transform(full_parent_transformation)
          # Garante que normal é válida
          world_normal.normalize! if world_normal.length > 0


          # Ajuste do Gizmo (usando primeiro vértice MUNDO como referência)
          comp_origin_world = outer_loop_world_verts.first
          comp_z_axis_world = world_normal # Eixo Z alinhado com a normal no mundo
          # Transformação que coloca a instância na posição/orientação correta no MUNDO
          instance_world_transformation = Geom::Transformation.new(comp_origin_world, comp_z_axis_world)
          # Transformação para trazer os vértices MUNDO para o LOCAL da definição
          origin_transformation_inv = instance_world_transformation.inverse

          # Vértices locais com Z=0 forçado
          outer_loop_local_verts = outer_loop_world_verts.map { |wv| p = wv.transform(origin_transformation_inv); p.z = 0; p }
          inner_loops_local_verts = inner_loops_world_verts.map do |loop_verts|
            loop_verts.map { |wv| p = wv.transform(origin_transformation_inv); p.z = 0; p }
          end

          # 3. Criar Definição
          comp_def_name = model.definitions.unique_name("Placa_#{thickness_inches.to_mm.round(1)}mm")
          comp_def = model.definitions.add(comp_def_name)
          def_ents = comp_def.entities

          # --- Criação Explícita de Todas as Faces Planas ---
          faces_to_delete_later = []

          # 4. Add outer base face
          base_face_outer = def_ents.add_face(outer_loop_local_verts)
          raise "Falha ao criar face base externa." unless base_face_outer&.valid?
          base_face_outer.reverse! if base_face_outer.normal.dot(Z_AXIS) < 0

          # 5. Add inner base faces (holes)
          inner_loops_local_verts.each_with_index { |iloop,idx| next if iloop.length<3; begin; iface=def_ents.add_face(iloop); if iface&.valid?; iface.reverse! if iface.normal.dot(Z_AXIS)<0; faces_to_delete_later<<iface; else; puts "Aviso: Falha face base int furo #{idx}."; end; rescue=>e; puts "Aviso: Erro face base int furo #{idx}: #{e.message}."; end }

          # 6. Calculate top vertices
          vec_z_offset = Geom::Vector3d.new(0, 0, -thickness_inches)
          outer_loop_top_verts = outer_loop_local_verts.map { |p| p.offset(vec_z_offset) }
          inner_loops_top_verts = inner_loops_local_verts.map { |lv| lv.map { |p| p.offset(vec_z_offset) } }

          # 7. Add outer top face
          top_face_outer = def_ents.add_face(outer_loop_top_verts)
          raise "Falha ao criar face topo externa." unless top_face_outer&.valid?
          # Não inverter
          top_face_outer.reverse! if top_face_outer.normal.dot(Z_AXIS) > 0
          # 8. Add inner top faces (holes)
          inner_loops_top_verts.each_with_index { |itop,idx| next if itop.length<3; begin; iface=def_ents.add_face(itop); if iface&.valid?; iface.reverse! if iface.normal.dot(Z_AXIS)<0; faces_to_delete_later<<iface; else; puts "Aviso: Falha face topo int furo #{idx}."; end; rescue=>e; puts "Aviso: Erro face topo int furo #{idx}: #{e.message}."; end }

          # --- Add Side Walls ---
          # 9. Outer walls
          num_outer=outer_loop_local_verts.length; (0...num_outer).each { |i| v1=outer_loop_local_verts[i];v2=outer_loop_local_verts[(i+1)%num_outer];next if v1.distance(v2)<TOLERANCE;v1t=outer_loop_top_verts[i];v2t=outer_loop_top_verts[(i+1)%num_outer];begin;def_ents.add_face(v1,v2,v2t,v1t);rescue=>e;puts "Aviso: Face lat ext #{i}: #{e.message}.";end }
          # 10. Inner walls
          inner_loops_local_verts.each_with_index { |iloop,idx| next if iloop.length<3;itop=inner_loops_top_verts[idx];num_in=iloop.length;(0...num_in).each { |i| v1=iloop[i];v2=iloop[(i+1)%num_in];next if v1.distance(v2)<TOLERANCE;v1t=itop[i];v2t=itop[(i+1)%num_in];begin;def_ents.add_face(v1,v1t,v2t,v2);rescue=>e;puts "Aviso: Face lat int furo #{idx}, seg #{i}: #{e.message}.";end } }

          # --- Final Step: Erase Inner Faces ---
          # 11. Erase collected inner faces
          valid_faces = faces_to_delete_later.select(&:valid?); if valid_faces.any?; puts "   - Apagando #{valid_faces.count} faces internas..."; def_ents.erase_entities(valid_faces); else; puts "Aviso: Nenhuma face interna marcada/válida." if inner_loops_local_verts.any?; end

          # 12. Criar Instância
          # <<<< CORREÇÃO: Adiciona no CONTEXTO correto e usa transformação MUNDO >>>>
          target_entities = original_face.parent.entities # Onde a instância será criada
          new_instance = target_entities.add_instance(comp_def, instance_world_transformation)
          # <<<< FIM CORREÇÃO >>>>

          new_instance.name = comp_def_name if new_instance.respond_to?(:name=)

          return new_instance

        rescue => e # Captura qualquer erro
          puts "Erro detalhado em create_component_geometry (Face Original ID: #{original_face.entityID}): #{e.message}"
          if comp_def&.valid?
            puts "Aviso: Definição '#{comp_def.name}' pode conter geometria parcial."
            model.definitions.remove(comp_def) if comp_def.instances.empty? rescue nil
          end
          return nil
        end
      end # End create_component_geometry

    end # module FaceToBoard
  end # module MockupTools
end # module Rjv