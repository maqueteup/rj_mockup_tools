# encoding: UTF-8
# face_to_board_improved.rb
# Módulo para converter faces em placas com UCS inteligente

require 'sketchup.rb'

module Rjv
  module MockupTools
    module FaceToBoard
      extend self
      
      # --- Tool Constants ---
      DEFAULT_THICKNESS_MM = 2.0
      Z_AXIS = Geom::Vector3d.new(0, 0, 1)
      TOLERANCE = 1e-4

      # --- Tool State ---
      @last_thickness_mm = DEFAULT_THICKNESS_MM

      # Função principal modular para converter faces em placas
      # Parâmetros:
      #   faces: Array de Face ou Face único, ou nil para usar seleção atual
      #   options: Hash com opções (opcional)
      #     - thickness_mm: espessura da placa em mm (padrão: pergunta ao usuário)
      #     - reset_ucs: aplica reset UCS após criação (padrão: true)
      #     - ucs_mode: modo do UCS (:intelligent, :bottom_left, :center) (padrão: :intelligent)
      #     - silent: não mostra mensagens de UI (padrão: false)
      #     - debug: mostra mensagens de debug (padrão: false)
      #     - keep_original: mantém faces originais (padrão: false)
      #
      # Retorna: Hash com resultados
      #   - success: true/false
      #   - created_components: array com componentes criados
      #   - failed_faces: hash com faces que falharam
      #   - ucs_result: resultado do reset UCS (se aplicado)
      #   - message: mensagem descritiva
      def create_boards_from_faces(faces = nil, options = {})
        # Configurações padrão
        opts = {
          thickness_mm: nil,          # nil = pergunta ao usuário
          reset_ucs: true,
          ucs_mode: :intelligent,
          silent: false,
          debug: false,
          keep_original: false
        }.merge(options)
        
        model = Sketchup.active_model
        
        # Se não foram fornecidas faces, usa a seleção atual
        if faces.nil?
          selection = model.selection
          faces = selection.grep(Sketchup::Face).select(&:valid?)
        else
          # Normaliza entrada para array
          faces = [faces] unless faces.is_a?(Array)
          faces = faces.compact.select { |f| f.is_a?(Sketchup::Face) && f.valid? }
        end
        
        if faces.empty?
          message = "Nenhuma face válida encontrada para converter"
          UI.messagebox(message) unless opts[:silent]
          return {
            success: false,
            created_components: [],
            failed_faces: {},
            ucs_result: nil,
            message: message
          }
        end
        
        # Obtém espessura
        thickness_mm = opts[:thickness_mm]
        if thickness_mm.nil? && !opts[:silent]
          thickness_mm = get_thickness_input()
          return {
            success: false,
            created_components: [],
            failed_faces: {},
            ucs_result: nil,
            message: "Operação cancelada pelo usuário"
          } unless thickness_mm
        elsif thickness_mm.nil?
          thickness_mm = @last_thickness_mm
        end
        
        thickness_inches = thickness_mm.mm
        @last_thickness_mm = thickness_mm
        
        puts "DEBUG: Convertendo #{faces.length} face(s) em placas de #{thickness_mm}mm" if opts[:debug]
        
        model.start_operation("Face to Board com UCS", true)
        
        begin
          created_components = []
          failed_faces_info = {}
          
          faces.each_with_index do |face, index|
            unless face.valid?
              puts "DEBUG: Pulando face #{index + 1} (inválida)" if opts[:debug]
              next
            end
            
            face_id = face.entityID
            puts "DEBUG: Processando face #{index + 1}/#{faces.length} (ID: #{face_id})" if opts[:debug]
            
            begin
              # Cria o componente da placa
              new_instance = create_component_geometry(face, thickness_inches, model, opts)
              
              if new_instance && new_instance.valid?
                created_components << new_instance
                puts "DEBUG: ✅ Placa criada para face #{face_id}" if opts[:debug]
                
                # Remove face original se solicitado
                unless opts[:keep_original]
                  cleanup_original_face(face, opts)
                end
              else
                failed_faces_info[face_id] = "Falha na criação da geometria"
                puts "DEBUG: ❌ Falha ao criar placa para face #{face_id}" if opts[:debug]
              end
              
            rescue => e
              error_msg = "Erro: #{e.message}"
              failed_faces_info[face_id] = error_msg
              puts "DEBUG: ❌ Erro na face #{face_id}: #{error_msg}" if opts[:debug]
            end
          end
          
          model.commit_operation
          
          # Aplica Reset UCS se solicitado
          ucs_result = nil
          if opts[:reset_ucs] && !created_components.empty?
            puts "DEBUG: Aplicando Reset UCS nos componentes criados..." if opts[:debug]
            
            if defined?(Rjv::MockupTools::ResetUCS)
              ucs_result = ResetUCS.reset_ucs_smart(
                created_components,
                {
                  detection_mode: opts[:ucs_mode],
                  use_sheet_detection: true,
                  silent: opts[:silent],
                  debug: opts[:debug]
                }
              )
              
              if opts[:debug]
                if ucs_result[:success]
                  puts "DEBUG: ✅ Reset UCS aplicado - #{ucs_result[:instances_updated]} instância(s) atualizadas"
                else
                  puts "DEBUG: ⚠️ Reset UCS falhou: #{ucs_result[:message]}"
                end
              end
            else
              puts "DEBUG: Módulo ResetUCS não disponível" if opts[:debug]
              ucs_result = { success: false, message: "Módulo ResetUCS não disponível" }
            end
          end
          
          # Seleciona componentes criados
          unless opts[:silent] || created_components.empty?
            begin
              model.selection.clear
              model.selection.add(created_components)
            rescue => e
              puts "DEBUG: Erro ao selecionar componentes: #{e.message}" if opts[:debug]
            end
          end
          
          # Resultado final
          success_count = created_components.length
          failed_count = failed_faces_info.keys.length
          
          message = build_result_message(success_count, failed_count, ucs_result, opts)
          
          # Exibe mensagem de resultado
          unless opts[:silent]
            if success_count > 0
              if failed_count > 0
                UI.messagebox(message)
              else
                Sketchup.status_text = message
              end
            elsif failed_count > 0
              UI.messagebox("Falha ao processar #{failed_count} face(s) selecionada(s).\nVerifique o console Ruby.")
            end
          end
          
          return {
            success: failed_count == 0,
            created_components: created_components,
            failed_faces: failed_faces_info,
            ucs_result: ucs_result,
            message: message
          }
          
        rescue => e
          model.abort_operation
          error_msg = "Erro durante conversão: #{e.message}"
          puts "ERROR: #{error_msg}" if opts[:debug]
          UI.messagebox(error_msg) unless opts[:silent]
          
          return {
            success: false,
            created_components: [],
            failed_faces: { "Erro geral" => e.message },
            ucs_result: nil,
            message: error_msg
          }
        end
      end
      
      # Função de conveniência para usar com seleção atual (mantém compatibilidade)
      def run
        return create_boards_from_faces(
          nil,
          {
            reset_ucs: true,
            ucs_mode: :intelligent,
            silent: false,
            debug: false
          }
        )
      end
      
      # Função de conveniência SEM reset UCS
      def create_boards_only(faces = nil, options = {})
        opts = { reset_ucs: false }.merge(options)
        return create_boards_from_faces(faces, opts)
      end
      
      # Função de conveniência COM reset UCS forçado
      def create_boards_with_smart_ucs(faces = nil, options = {})
        opts = {
          reset_ucs: true,
          ucs_mode: :intelligent
        }.merge(options)
        return create_boards_from_faces(faces, opts)
      end
      
      # Função de conveniência para manter faces originais
      def create_boards_keep_original(faces = nil, options = {})
        opts = { keep_original: true }.merge(options)
        return create_boards_from_faces(faces, opts)
      end
      
      private
      
      # Obtém entrada de espessura do usuário
      def get_thickness_input
        prompts = ["Espessura da Placa (mm):"]
        defaults = [@last_thickness_mm.to_s]
        input = UI.inputbox(prompts, defaults, "Mockup Tools - Face to Board")
        return nil unless input # User cancelled
        
        begin
          thickness_mm = input[0].to_f
          if thickness_mm <= TOLERANCE
            UI.messagebox("A espessura deve ser positiva.")
            return nil
          end
          return thickness_mm
        rescue ArgumentError
          UI.messagebox("Valor inválido.")
          return nil
        end
      end
      
      # Constrói mensagem de resultado
      def build_result_message(success_count, failed_count, ucs_result, opts)
        message = "#{success_count} placa(s) criada(s)"
        
        if failed_count > 0
          message += ", #{failed_count} falharam"
        end
        
        if opts[:reset_ucs] && ucs_result
          if ucs_result[:success]
            message += ", UCS ajustado"
          else
            message += ", UCS NÃO ajustado"
          end
        end
        
        message += "."
        return message
      end
      
      # Remove face original e arestas isoladas
      def cleanup_original_face(face, opts)
        return unless face.valid? && !face.deleted?
        
        begin
          target_entities = face.parent.entities
          edges_to_delete = face.edges.select { |e| e.valid? && e.faces.length == 1 }
          entities_to_erase = [face] + edges_to_delete
          target_entities.erase_entities(entities_to_erase.select(&:valid?))
          
          puts "DEBUG: Face original removida" if opts[:debug]
        rescue => e
          puts "DEBUG: Erro ao remover face original: #{e.message}" if opts[:debug]
        end
      end
      
      # Obtém transformação completa de contextos aninhados
      def get_full_transformation(entity)
        transformation = Geom::Transformation.new # Start with identity
        current = entity.parent
        
        while current.respond_to?(:transformation) && !current.is_a?(Sketchup::Model)
          # Combine parent's transformation (pre-multiply)
          transformation = current.transformation * transformation
          
          # Move up the hierarchy
          if current.is_a?(Sketchup::ComponentDefinition)
            # Para definições, pega a primeira instância para continuar subindo
            instance_parent = current.instances.first
            current = instance_parent ? instance_parent.parent : Sketchup.active_model
          else
            # Para Group ou ComponentInstance, pega o parent
            current = current.parent
          end
        end
        
        transformation
      end
      
      # Cria a geometria do componente da placa
      def create_component_geometry(original_face, thickness_inches, model, opts = {})
        comp_def = nil
        
        begin
          # 1. Validações
          unless original_face.valid? && !original_face.deleted?
            raise "Face original inválida (ID: #{original_face.entityID})"
          end
          
          puts "DEBUG: Iniciando criação de geometria..." if opts[:debug]
          
          # 2. Obter dados e transformações
          full_parent_transformation = get_full_transformation(original_face)
          
          # Calcula vértices e normal no espaço do MODELO (World Coordinates)
          outer_loop_world_verts = original_face.outer_loop.vertices.map { |v| 
            v.position.transform(full_parent_transformation) 
          }
          
          inner_loops_world_verts = original_face.loops.select { |l| !l.outer? }.map do |loop|
            loop.vertices.map { |v| v.position.transform(full_parent_transformation) }
          end
          
          # Normal transformada para coordenadas mundo
          world_normal = original_face.normal.transform(full_parent_transformation)
          world_normal.normalize! if world_normal.length > 0
          
          puts "DEBUG: #{outer_loop_world_verts.length} vértices externos, #{inner_loops_world_verts.length} furos" if opts[:debug]
          
          # 3. Configuração do gizmo
          comp_origin_world = outer_loop_world_verts.first
          comp_z_axis_world = world_normal
          
          # Transformação da instância no mundo
          instance_world_transformation = Geom::Transformation.new(comp_origin_world, comp_z_axis_world)
          origin_transformation_inv = instance_world_transformation.inverse
          
          # Vértices locais com Z=0 forçado
          outer_loop_local_verts = outer_loop_world_verts.map { |wv| 
            p = wv.transform(origin_transformation_inv)
            p.z = 0
            p
          }
          
          inner_loops_local_verts = inner_loops_world_verts.map do |loop_verts|
            loop_verts.map { |wv| 
              p = wv.transform(origin_transformation_inv)
              p.z = 0
              p
            }
          end
          
          # 4. Criar definição
          thickness_mm = (thickness_inches * 25.4).round(1)
          comp_def_name = model.definitions.unique_name("Placa_#{thickness_mm}mm")
          comp_def = model.definitions.add(comp_def_name)
          def_ents = comp_def.entities
          
          puts "DEBUG: Criando definição '#{comp_def_name}'" if opts[:debug]
          
          # 5. Criar geometria da placa
          result = create_plate_geometry(
            def_ents, 
            outer_loop_local_verts, 
            inner_loops_local_verts, 
            thickness_inches, 
            opts
          )
          
          unless result[:success]
            raise result[:message]
          end
          
          # 6. Criar instância no contexto correto
          target_entities = original_face.parent.entities
          new_instance = target_entities.add_instance(comp_def, instance_world_transformation)
          new_instance.name = comp_def_name if new_instance.respond_to?(:name=)
          
          puts "DEBUG: ✅ Instância criada com sucesso" if opts[:debug]
          
          return new_instance
          
        rescue => e
          error_msg = "Erro na criação: #{e.message}"
          puts "DEBUG: ❌ #{error_msg}" if opts[:debug]
          
          # Limpa definição se houver erro
          if comp_def&.valid?
            model.definitions.remove(comp_def) if comp_def.instances.empty? rescue nil
          end
          
          return nil
        end
      end
      
      # Cria a geometria da placa (faces e paredes)
      def create_plate_geometry(def_ents, outer_verts, inner_loops_verts, thickness, opts)
        begin
          faces_to_delete_later = []
          
          puts "DEBUG: Criando faces da placa..." if opts[:debug]
          
          # Face base externa
          base_face_outer = def_ents.add_face(outer_verts)
          unless base_face_outer&.valid?
            return { success: false, message: "Falha ao criar face base externa" }
          end
          base_face_outer.reverse! if base_face_outer.normal.dot(Z_AXIS) < 0
          
          # Faces base internas (furos)
          inner_loops_verts.each_with_index do |iloop, idx|
            next if iloop.length < 3
            
            begin
              iface = def_ents.add_face(iloop)
              if iface&.valid?
                iface.reverse! if iface.normal.dot(Z_AXIS) < 0
                faces_to_delete_later << iface
              else
                puts "DEBUG: Falha na face base interna #{idx}" if opts[:debug]
              end
            rescue => e
              puts "DEBUG: Erro na face base interna #{idx}: #{e.message}" if opts[:debug]
            end
          end
          
          # Vértices do topo
          vec_z_offset = Geom::Vector3d.new(0, 0, -thickness)
          outer_top_verts = outer_verts.map { |p| p.offset(vec_z_offset) }
          inner_loops_top_verts = inner_loops_verts.map { |lv| 
            lv.map { |p| p.offset(vec_z_offset) }
          }
          
          # Face topo externa
          top_face_outer = def_ents.add_face(outer_top_verts)
          unless top_face_outer&.valid?
            return { success: false, message: "Falha ao criar face topo externa" }
          end
          top_face_outer.reverse! if top_face_outer.normal.dot(Z_AXIS) > 0
          
          # Faces topo internas (furos)
          inner_loops_top_verts.each_with_index do |itop, idx|
            next if itop.length < 3
            
            begin
              iface = def_ents.add_face(itop)
              if iface&.valid?
                iface.reverse! if iface.normal.dot(Z_AXIS) < 0
                faces_to_delete_later << iface
              else
                puts "DEBUG: Falha na face topo interna #{idx}" if opts[:debug]
              end
            rescue => e
              puts "DEBUG: Erro na face topo interna #{idx}: #{e.message}" if opts[:debug]
            end
          end
          
          # Paredes externas
          num_outer = outer_verts.length
          (0...num_outer).each do |i|
            v1 = outer_verts[i]
            v2 = outer_verts[(i+1) % num_outer]
            next if v1.distance(v2) < TOLERANCE
            
            v1t = outer_top_verts[i]
            v2t = outer_top_verts[(i+1) % num_outer]
            
            begin
              def_ents.add_face(v1, v2, v2t, v1t)
            rescue => e
              puts "DEBUG: Erro na parede externa #{i}: #{e.message}" if opts[:debug]
            end
          end
          
          # Paredes internas (furos)
          inner_loops_verts.each_with_index do |iloop, idx|
            next if iloop.length < 3
            
            itop = inner_loops_top_verts[idx]
            num_in = iloop.length
            
            (0...num_in).each do |i|
              v1 = iloop[i]
              v2 = iloop[(i+1) % num_in]
              next if v1.distance(v2) < TOLERANCE
              
              v1t = itop[i]
              v2t = itop[(i+1) % num_in]
              
              begin
                def_ents.add_face(v1, v1t, v2t, v2)
              rescue => e
                puts "DEBUG: Erro na parede interna #{idx}, segmento #{i}: #{e.message}" if opts[:debug]
              end
            end
          end
          
          # Remove faces internas dos furos
          valid_faces = faces_to_delete_later.select(&:valid?)
          if valid_faces.any?
            puts "DEBUG: Removendo #{valid_faces.count} faces internas" if opts[:debug]
            def_ents.erase_entities(valid_faces)
          elsif inner_loops_verts.any?
            puts "DEBUG: Nenhuma face interna para remover" if opts[:debug]
          end
          
          return { success: true, message: "Geometria criada com sucesso" }
          
        rescue => e
          return { success: false, message: "Erro na criação da geometria: #{e.message}" }
        end
      end
      
      # Função para analisar faces selecionadas
      def analyze_faces(faces = nil)
        if faces.nil?
          model = Sketchup.active_model
          selection = model.selection
          faces = selection.grep(Sketchup::Face).select(&:valid?)
        else
          faces = [faces] unless faces.is_a?(Array)
          faces = faces.compact.select { |f| f.is_a?(Sketchup::Face) && f.valid? }
        end
        
        if faces.empty?
          puts "=== ANÁLISE DE FACES ==="
          puts "Nenhuma face selecionada"
          puts "======================="
          return
        end
        
        puts "\n=== ANÁLISE DE FACES ==="
        puts "Faces selecionadas: #{faces.length}"
        
        faces.each_with_index do |face, index|
          puts "\n#{index + 1}. Face ID: #{face.entityID}"
          puts "   Área: #{(face.area * 1000000).round(1)}mm²"
          puts "   Normal: #{face.normal}"
          puts "   Contexto: #{face.parent.class}"
          puts "   Loops: #{face.loops.length} (#{face.loops.count { |l| !l.outer? }} furos)"
          
          if face.loops.length > 1
            puts "   Vértices externos: #{face.outer_loop.vertices.length}"
            face.loops.select { |l| !l.outer? }.each_with_index do |loop, i|
              puts "   Furo #{i+1}: #{loop.vertices.length} vértices"
            end
          else
            puts "   Vértices: #{face.outer_loop.vertices.length}"
          end
        end
        puts "=========================\n"
        
        return faces
      end
    end
  end
end