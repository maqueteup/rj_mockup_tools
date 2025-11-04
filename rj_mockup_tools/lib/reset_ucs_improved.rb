# encoding: UTF-8
# reset_ucs_improved.rb
# Módulo para resetar UCS (gizmo) de componentes de forma inteligente

require 'sketchup.rb'

module Rjv
  module MockupTools
    module ResetUCS
      extend self
      
      # Constantes
      TOLERANCE = 1e-4
      ORIGIN = Geom::Point3d.new(0, 0, 0)
      
      # Função principal modular para resetar UCS de componentes
      # Parâmetros:
      #   instances: Array de ComponentInstance ou ComponentInstance único, ou nil para usar seleção atual
      #   options: Hash com opções (opcional)
      #     - detection_mode: :intelligent (padrão), :bottom_left, :center
      #     - use_sheet_detection: true (padrão) - usa detector de chapas para posicionamento inteligente
      #     - silent: não mostra mensagens de UI (padrão: false)
      #     - debug: mostra mensagens de debug (padrão: false)
      #
      # Retorna: Hash com resultados
      #   - success: true/false
      #   - processed: número de definições processadas
      #   - failed: hash com definições que falharam
      #   - instances_updated: número total de instâncias atualizadas
      #   - message: mensagem descritiva
      def reset_ucs_smart(instances = nil, options = {})
        # Configurações padrão
        opts = {
          detection_mode: :intelligent,
          use_sheet_detection: true,
          silent: false,
          debug: false
        }.merge(options)
        
        # Se não foram fornecidos componentes, usa a seleção atual
        if instances.nil?
          model = Sketchup.active_model
          selection = model.selection
          instances = selection.grep(Sketchup::ComponentInstance)
        else
          # Normaliza entrada para array
          instances = [instances] unless instances.is_a?(Array)
          instances = instances.compact.select { |i| i.is_a?(Sketchup::ComponentInstance) }
        end
        
        if instances.empty?
          message = "Nenhuma instância de componente encontrada"
          UI.messagebox(message) unless opts[:silent]
          return {
            success: false,
            processed: 0,
            failed: {},
            instances_updated: 0,
            message: message
          }
        end
        
        model = instances.first.model
        instances_by_definition = instances.group_by(&:definition)
        processed_definitions = 0
        failed_definitions = {}
        total_instances_updated = 0
        
        puts "DEBUG: Processando #{instances_by_definition.keys.length} definição(ões) com modo #{opts[:detection_mode]}" if opts[:debug]
        
        model.start_operation("Reset UCS Inteligente", true)
        
        begin
          instances_by_definition.each do |definition, selected_instances|
            result = process_single_definition(definition, opts)
            
            if result[:success]
              processed_definitions += 1
              total_instances_updated += result[:instances_updated]
              puts "DEBUG: ✅ #{definition.name} processado - #{result[:instances_updated]} instância(s) atualizadas" if opts[:debug]
            else
              failed_definitions[definition.name] = result[:message]
              puts "DEBUG: ❌ #{definition.name} falhou: #{result[:message]}" if opts[:debug]
            end
          end
          
          model.commit_operation
          
          # Mensagem de resultado
          unless opts[:silent]
            if processed_definitions > 0
              message = "#{processed_definitions} definição(ões) teve(ram) seu UCS ajustado."
              if failed_definitions.any?
                message += "\nFalha ao processar #{failed_definitions.count} definição(ões): #{failed_definitions.keys.join(', ')}"
                UI.messagebox(message)
              else
                Sketchup.status_text = message
              end
            elsif failed_definitions.any?
              UI.messagebox("Falha ao processar #{failed_definitions.count} definição(ões) selecionada(s):\n#{failed_definitions.map{|k,v| "#{k}: #{v}"}.join("\n")}")
            else
              UI.messagebox("Nenhuma definição de componente válida encontrada na seleção.")
            end
          end
          
          return {
            success: failed_definitions.empty?,
            processed: processed_definitions,
            failed: failed_definitions,
            instances_updated: total_instances_updated,
            message: "#{processed_definitions} processadas, #{total_instances_updated} instâncias atualizadas"
          }
          
        rescue => e
          model.abort_operation
          error_msg = "Erro durante reset UCS: #{e.message}"
          puts "ERROR: #{error_msg}" if opts[:debug]
          UI.messagebox(error_msg) unless opts[:silent]
          
          return {
            success: false,
            processed: 0,
            failed: { "Erro geral" => e.message },
            instances_updated: 0,
            message: error_msg
          }
        end
      end
      
      # Função de conveniência para usar com seleção atual (mantém compatibilidade)
      def run
        return reset_ucs_smart(nil, { detection_mode: :intelligent, debug: false })
      end
      
      # Função de conveniência para modo bottom-left clássico
      def reset_ucs_bottom_left(instances = nil, options = {})
        opts = { detection_mode: :bottom_left }.merge(options)
        return reset_ucs_smart(instances, opts)
      end
      
      # Função de conveniência para modo inteligente (padrão)
      def reset_ucs_intelligent(instances = nil, options = {})
        opts = { detection_mode: :intelligent }.merge(options)
        return reset_ucs_smart(instances, opts)
      end
      
      # Função de conveniência para centralizar UCS
      def reset_ucs_center(instances = nil, options = {})
        opts = { detection_mode: :center }.merge(options)
        return reset_ucs_smart(instances, opts)
      end
      
      private
      
      # Processa uma única definição de componente
      def process_single_definition(definition, opts = {})
        puts "\nDEBUG: === Processando definição: #{definition.name} ===" if opts[:debug]
        
        if definition.entities.count == 0
          return { success: false, message: "Definição vazia", instances_updated: 0 }
        end
        
        bounds = definition.bounds
        if bounds.empty?
          return { success: false, message: "Bounding Box vazia", instances_updated: 0 }
        end
        
        # Calcula novo ponto de origem baseado no modo de detecção
        new_origin = calculate_smart_origin(definition, bounds, opts)
        
        unless new_origin
          return { success: false, message: "Falha ao calcular nova origem", instances_updated: 0 }
        end
        
        puts "DEBUG: Nova origem calculada: #{new_origin}" if opts[:debug]
        
        # Verifica se já está na posição correta
        if new_origin.distance(ORIGIN) < TOLERANCE
          puts "DEBUG: UCS já está correto" if opts[:debug]
          return { 
            success: true, 
            message: "UCS já estava correto", 
            instances_updated: definition.instances.length 
          }
        end
        
        # Aplica as transformações
        result = apply_ucs_transformation(definition, new_origin, opts)
        
        return result
      end
      
      # Calcula a nova origem de forma inteligente
      def calculate_smart_origin(definition, bounds, opts = {})
        mode = opts[:detection_mode] || :intelligent
        
        puts "DEBUG: Modo de detecção: #{mode}" if opts[:debug]
        
        case mode
        when :bottom_left
          return calculate_bottom_left_origin(bounds, opts)
        when :center
          return bounds.center
        when :intelligent
          return calculate_intelligent_origin(definition, bounds, opts)
        else
          puts "DEBUG: Modo desconhecido, usando bottom_left" if opts[:debug]
          return calculate_bottom_left_origin(bounds, opts)
        end
      end
      
      # Calcula origem no canto inferior esquerdo (método clássico)
      def calculate_bottom_left_origin(bounds, opts = {})
        corners = (0..7).map { |i| bounds.corner(i) }
        bottom_left = corners.min_by { |c| [c.z, c.x, c.y] }
        
        puts "DEBUG: Bottom-left clássico: #{bottom_left}" if opts[:debug]
        return bottom_left
      end
      
      # Calcula origem de forma inteligente baseada na geometria
      def calculate_intelligent_origin(definition, bounds, opts = {})
        # 1. Primeiro, tenta usar detecção de chapas se disponível
        if opts[:use_sheet_detection] && defined?(Rjv::MockupTools::SheetDetector)
          puts "DEBUG: Tentando detecção inteligente com SheetDetector..." if opts[:debug]
          
          # Cria uma instância temporária para análise
          temp_instance = create_temp_instance_for_analysis(definition)
          
          if temp_instance
            sheet_result = SheetDetector.detect_sheets(temp_instance, { debug: false, silent: true })
            
            # Limpa a instância temporária
            temp_instance.erase! if temp_instance.valid?
            
            if sheet_result[:is_sheet]
              puts "DEBUG: Componente detectado como chapa - usando posicionamento específico para chapas" if opts[:debug]
              return calculate_sheet_origin(definition, bounds, sheet_result, opts)
            else
              puts "DEBUG: Componente NÃO é chapa - usando detecção geométrica geral" if opts[:debug]
            end
          end
        end
        
        # 2. Se não é chapa ou detector não disponível, usa análise geométrica
        return calculate_geometric_origin(definition, bounds, opts)
      end
      
      # Cria instância temporária para análise (sem afetar o modelo)
      def create_temp_instance_for_analysis(definition)
        begin
          # Encontra qualquer entidade pai onde possamos criar temporariamente
          model = definition.model
          temp_instance = model.entities.add_instance(definition, Geom::Transformation.new)
          return temp_instance
        rescue => e
          puts "DEBUG: Erro ao criar instância temporária: #{e.message}"
          return nil
        end
      end
      
      # Calcula origem específica para chapas
      def calculate_sheet_origin(definition, bounds, sheet_result, opts = {})
        puts "DEBUG: Calculando origem para chapa..." if opts[:debug]
        
        # Para chapas, posiciona na face inferior no canto que otimiza o layout
        faces = definition.entities.grep(Sketchup::Face)
        
        # Encontra face inferior (maior área com normal Z-)
        bottom_faces = faces.select { |face| face.normal.z < -0.7 }
        
        if bottom_faces.any?
          bottom_face = bottom_faces.max_by(&:area)
          
          # Encontra o vértice da face inferior mais próximo do canto inferior-esquerdo
          vertices = bottom_face.vertices.map(&:position)
          
          # Ordena por Z (menor primeiro), depois X (menor primeiro), depois Y (menor primeiro)
          best_vertex = vertices.min_by { |v| [v.z, v.x, v.y] }
          
          puts "DEBUG: Origem da chapa no vértice: #{best_vertex}" if opts[:debug]
          return best_vertex
        end
        
        # Fallback para método clássico se não encontrar face inferior
        puts "DEBUG: Fallback para bottom-left (não encontrou face inferior)" if opts[:debug]
        return calculate_bottom_left_origin(bounds, opts)
      end
      
      # Calcula origem baseada na análise geométrica geral
      def calculate_geometric_origin(definition, bounds, opts = {})
        puts "DEBUG: Calculando origem geométrica geral..." if opts[:debug]
        
        # Analisa a geometria para encontrar o ponto de apoio mais provável
        faces = definition.entities.grep(Sketchup::Face)
        edges = definition.entities.grep(Sketchup::Edge)
        
        if faces.any?
          # Procura faces horizontais (candidatas a base)
          horizontal_faces = faces.select { |face| 
            face.normal.z.abs > 0.8  # Normal próxima de vertical (face horizontal)
          }
          
          if horizontal_faces.any?
            # Encontra a face horizontal mais baixa
            bottom_faces = horizontal_faces.select { |face| face.normal.z < 0 }  # Normal apontando para baixo
            
            if bottom_faces.any?
              bottom_face = bottom_faces.min_by { |face| 
                # Usa o Z médio da face
                vertices = face.vertices.map(&:position)
                vertices.map(&:z).sum / vertices.length.to_f
              }
              
              # Pega o vértice mais "inferior-esquerdo" desta face
              vertices = bottom_face.vertices.map(&:position)
              best_vertex = vertices.min_by { |v| [v.z, v.x, v.y] }
              
              puts "DEBUG: Origem baseada em face de apoio: #{best_vertex}" if opts[:debug]
              return best_vertex
            end
          end
        end
        
        # Fallback: método clássico
        puts "DEBUG: Fallback para bottom-left clássico" if opts[:debug]
        return calculate_bottom_left_origin(bounds, opts)
      end
      
      # Aplica as transformações de UCS
      def apply_ucs_transformation(definition, new_origin, opts = {})
        puts "DEBUG: Aplicando transformação UCS..." if opts[:debug]
        
        begin
          # T1: Move a geometria interna para a origem [0,0,0]
          move_geometry_to_origin_tf = Geom::Transformation.translation(new_origin.vector_to(ORIGIN))
          
          # T2: Transformação para DESFAZER o movimento interno (compensação)
          keep_instance_in_place_tf = move_geometry_to_origin_tf.inverse
          
          # Aplica T1 à definição
          entities_to_transform = definition.entities.to_a
          definition.entities.transform_entities(move_geometry_to_origin_tf, entities_to_transform)
          
          # Aplica a compensação a TODAS as instâncias desta definição
          all_instances_of_def = definition.instances.to_a
          instances_updated = 0
          
          all_instances_of_def.each do |inst|
            next unless inst.valid?
            
            old_transform = inst.transformation
            # A nova transformação mantém a instância onde estava
            new_transform = old_transform * keep_instance_in_place_tf
            inst.transformation = new_transform
            instances_updated += 1
          end
          
          puts "DEBUG: #{instances_updated} instância(s) atualizadas" if opts[:debug]
          
          return {
            success: true,
            message: "UCS resetado com sucesso",
            instances_updated: instances_updated
          }
          
        rescue => e
          return {
            success: false,
            message: "Erro ao aplicar transformação: #{e.message}",
            instances_updated: 0
          }
        end
      end
      
      # Função para analisar componentes antes de aplicar reset
      def analyze_components(instances = nil)
        if instances.nil?
          model = Sketchup.active_model
          selection = model.selection
          instances = selection.grep(Sketchup::ComponentInstance)
        else
          instances = [instances] unless instances.is_a?(Array)
          instances = instances.compact.select { |i| i.is_a?(Sketchup::ComponentInstance) }
        end
        
        if instances.empty?
          puts "=== ANÁLISE DE UCS ==="
          puts "Nenhum componente selecionado"
          puts "====================="
          return
        end
        
        instances_by_definition = instances.group_by(&:definition)
        
        puts "\n=== ANÁLISE DE UCS ==="
        puts "Componentes selecionados: #{instances.length}"
        puts "Definições únicas: #{instances_by_definition.keys.length}"
        
        instances_by_definition.each_with_index do |(definition, def_instances), index|
          puts "\n#{index + 1}. Definição: '#{definition.name}'"
          puts "   Instâncias: #{def_instances.length}"
          puts "   Entidades: #{definition.entities.length}"
          
          if definition.entities.length > 0
            bounds = definition.bounds
            corners = (0..7).map { |i| bounds.corner(i) }
            current_origin = corners.min_by { |c| [c.z, c.x, c.y] }
            
            puts "   Bounds: #{bounds.width.to_mm.round(1)} x #{bounds.height.to_mm.round(1)} x #{bounds.depth.to_mm.round(1)}mm"
            puts "   Origem atual: #{current_origin}"
            puts "   Precisa reset: #{current_origin.distance(ORIGIN) > TOLERANCE ? 'SIM' : 'NÃO'}"
            
            # Testa detecção inteligente se disponível
            if defined?(Rjv::MockupTools::SheetDetector)
              temp_instance = create_temp_instance_for_analysis(definition)
              if temp_instance
                sheet_result = SheetDetector.detect_sheets(temp_instance, { debug: false, silent: true })
                puts "   É chapa: #{sheet_result[:is_sheet] ? 'SIM' : 'NÃO'}"
                temp_instance.erase! if temp_instance.valid?
              end
            end
          end
        end
        puts "======================\n"
        
        return instances_by_definition
      end
    end
  end
end