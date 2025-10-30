# encoding: UTF-8
# Mockup Tools RJV - Orient Z Faces Tool Module

require 'sketchup.rb'

module Rjv
  module MockupTools
    module OrientZFaces

      # --- Constantes ---
      TOLERANCE = 1e-4 # Tolerância para comparar Z e normais
      Z_AXIS = Geom::Vector3d.new(0, 0, 1).freeze

      # --- Método principal ---
      def self.run
        model = Sketchup.active_model
        selection = model.selection.to_a
        valid_targets = selection.select do |e|
          e.valid? && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance))
        end

        if valid_targets.empty?
          UI.messagebox("Selecione Grupos ou Componentes para orientar as faces Z.")
          return
        end

        definitions_to_process = {}
        groups_to_process = []
        valid_targets.each do |entity|
          if entity.is_a?(Sketchup::ComponentInstance); definitions_to_process[entity.definition] = true;
          elsif entity.is_a?(Sketchup::Group); groups_to_process << entity; end
        end

        total_reversed_count = 0
        processed_objects = 0

        model.start_operation("Orient Z Faces", true)

        # Processa Definições
        definitions_to_process.keys.each do |definition|
          next unless definition.valid?
          puts "  - Orientando Z Faces: Def '#{definition.name}'"
          reversed_count = orient_z_in_context(definition.entities)
          if reversed_count >= 0; total_reversed_count += reversed_count; processed_objects += 1; end
        end

        # Processa Grupos
        groups_to_process.each do |group|
           next unless group.valid?
           puts "  - Orientando Z Faces: Grupo '#{group.name || '(S/N)'}'"
           reversed_count = orient_z_in_context(group.entities)
           if reversed_count >= 0; total_reversed_count += reversed_count; processed_objects += 1; end
        end

        model.commit_operation

        UI.messagebox("#{total_reversed_count} face(s) invertida(s) em #{processed_objects} objeto(s) para corrigir orientação Z.")
        Sketchup.status_text = "Orientação Z concluída."

      end # Fim self.run


      # --- Lógica para orientar faces Z em um contexto ---
      # Retorna o número de faces invertidas ou -1 em erro
      private_class_method def self.orient_z_in_context(entities)
        reversed_count = 0
        begin
            all_faces = entities.grep(Sketchup::Face).select(&:valid?)
            return 0 if all_faces.empty?

            # 1. Encontra o Z mínimo absoluto dentro do contexto
            min_z = Float::INFINITY
            all_faces.each do |face|
                face.vertices.each { |v| z = v.position.z; min_z = z if z < min_z }
            end
            # Se não encontrou nenhum Z válido (improvável com faces válidas)
            return 0 if min_z == Float::INFINITY

            # 2. Itera e inverte faces conforme necessário
            all_faces.each do |face|
                next unless face.valid? # Segurança extra
                begin
                    normal = face.normal
                    next unless normal.valid? # Pula faces com normal inválida

                    # Determina se a face está no plano Z mínimo (aproximadamente)
                    # Verifica se TODOS os vértices estão próximos do min_z no eixo Z
                    is_bottom_face = face.vertices.all? { |v| (v.position.z - min_z).abs < TOLERANCE }

                    if is_bottom_face
                        # É uma face inferior, GARANTE que normal aponta para -Z
                        if normal.parallel?(Z_AXIS) && normal.z > TOLERANCE # Se aponta para +Z
                           face.reverse!
                           reversed_count += 1
                           # puts "    - Invertendo face inferior #{face.entityID}"
                        elsif !normal.parallel?(Z_AXIS)
                            puts "    - Aviso: Face no plano Z mínimo #{face.entityID} não é horizontal!"
                        end
                    else
                        # NÃO é uma face inferior, GARANTE que normal NÃO aponta para -Z
                        if normal.parallel?(Z_AXIS) && normal.z < -TOLERANCE # Se aponta para -Z
                            face.reverse!
                            reversed_count += 1
                            # puts "    - Invertendo face não-inferior #{face.entityID}"
                        end
                        # Não nos importamos se normais laterais apontam para dentro ou fora aqui,
                        # apenas que não apontem para -Z.
                    end
                rescue => face_error
                    puts "    - Erro ao processar face #{face.entityID}: #{face_error.message}"
                    # Continua com as outras faces
                end
            end # Fim loop each face

            return reversed_count

        rescue => e # Erro geral
            puts "  - ERRO GERAL ao orientar faces Z: #{e.message}"
            puts e.backtrace.first(3)
            return -1 # Indica erro
        end
      end # Fim orient_z_in_context

    end # module OrientZFaces
  end # module MockupTools
end # module Rjv