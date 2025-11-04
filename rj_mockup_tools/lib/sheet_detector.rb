# encoding: UTF-8
# sheet_detector.rb
# Módulo para detectar se um componente é uma chapa

require 'sketchup.rb'

module Rjv
  module MockupTools
    module SheetDetector
      extend self
      
      # Função principal para detectar se componente(s) são chapas
      # Parâmetros:
      #   instances: Array de ComponentInstance ou ComponentInstance único, ou nil para usar seleção atual
      #   options: Hash com opções (opcional)
      #     - tolerance: tolerância para considerar faces coplanares (padrão: 0.0005 = 0.5mm)
      #     - debug: mostra informações detalhadas (padrão: false)
      #     - silent: não mostra mensagens de UI (padrão: false)
      #
      # Retorna: Hash ou Array de Hash com resultados
      #   - is_sheet: true/false
      #   - z_is_smallest: true/false se Z é a menor dimensão
      #   - has_top_bottom_faces: true/false se tem faces superior e inferior
      #   - faces_are_coplanar: true/false se as faces Z são coplanares
      #   - dimensions: {x, y, z} dimensões do componente
      #   - thickness: espessura (dimensão Z)
      #   - top_face_area: área da face superior
      #   - bottom_face_area: área da face inferior
      #   - message: descrição do resultado
      def detect_sheets(instances = nil, options = {})
        # Configurações padrão
        opts = {
          tolerance: 0.0005,  # 0.5mm de tolerância (rigoroso)
          debug: false,
          silent: false
        }.merge(options)
        
        # Se não foram fornecidos componentes, usa a seleção atual
        if instances.nil?
          model = Sketchup.active_model
          selection = model.selection
          instances = selection.select { |e| e.is_a?(Sketchup::ComponentInstance) }
        else
          # Normaliza entrada para array
          instances = [instances] unless instances.is_a?(Array)
          instances = instances.compact.select { |i| i.is_a?(Sketchup::ComponentInstance) }
        end
        
        if instances.empty?
          message = "Nenhum componente encontrado para analisar"
          UI.messagebox(message) unless opts[:silent]
          return { 
            success: false, 
            message: message,
            results: []
          }
        end
        
        results = []
        sheet_count = 0
        
        instances.each do |instance|
          result = analyze_single_component(instance, opts)
          results << result
          sheet_count += 1 if result[:is_sheet]
        end
        
        # Mensagem de resultado
        unless opts[:silent]
          if instances.length == 1
            result = results.first
            if result[:is_sheet]
              UI.messagebox("✅ Este componente É uma chapa!\nEspessura: #{(result[:thickness] * 1000).round(2)}mm")
            else
              UI.messagebox("❌ Este componente NÃO é uma chapa.\n#{result[:message]}")
            end
          else
            UI.messagebox("📊 Análise: #{sheet_count} de #{instances.length} componente(s) são chapas.")
          end
        end
        
        # Se for apenas um componente, retorna o resultado direto
        if instances.length == 1
          return results.first
        else
          return {
            success: true,
            total_analyzed: instances.length,
            sheet_count: sheet_count,
            results: results,
            message: "#{sheet_count} de #{instances.length} são chapas"
          }
        end
      end
      
      # Função de conveniência para usar com seleção atual
      def run
        return detect_sheets(nil, { debug: true, silent: false })
      end
      
      # Função para detectar apenas chapas (filtra os resultados)
      def find_sheets_only(instances = nil, options = {})
        results = detect_sheets(instances, options.merge(silent: true))
        
        if results.is_a?(Array)
          # Múltiplos componentes
          sheets = results[:results].select { |r| r[:is_sheet] }
          return sheets
        else
          # Componente único
          return results[:is_sheet] ? [results] : []
        end
      end
      
      # Função para analisar um único componente
      def analyze_single_component(instance, opts = {})
        return { 
          is_sheet: false, 
          message: "Instância inválida" 
        } unless instance && instance.respond_to?(:definition)
        
        definition = instance.definition
        component_name = definition.name
        
        puts "\n=== ANALISANDO COMPONENTE: #{component_name} ===" if opts[:debug]
        
        # 1. VERIFICA DIMENSÕES
        bounds = get_component_bounds(definition)
        return { 
          is_sheet: false, 
          message: "Sem geometria válida" 
        } unless bounds
        
        width = bounds.width   # X
        height = bounds.height # Y
        depth = bounds.depth   # Z
        
        dimensions = { x: width, y: height, z: depth }
        
        puts "DEBUG: Dimensões - X: #{(width*1000).round(2)}mm, Y: #{(height*1000).round(2)}mm, Z: #{(depth*1000).round(2)}mm" if opts[:debug]
        
        # 2. VERIFICA SE Z É ESTRITAMENTE O MENOR EIXO
        z_is_smallest = (depth < width && depth < height)
        
        puts "DEBUG: Z é estritamente o menor eixo: #{z_is_smallest}" if opts[:debug]
        puts "DEBUG: Comparação - Z(#{(depth*1000).round(2)}mm) < X(#{(width*1000).round(2)}mm) E Z < Y(#{(height*1000).round(2)}mm)" if opts[:debug]
        
        if !z_is_smallest
          smallest_dims = [width, height, depth].sort
          if (depth - smallest_dims[0]).abs < 0.0001
            reason = "Z não é estritamente menor (Z=#{(depth*1000).round(2)}mm é igual à menor dimensão)"
          elsif smallest_dims[0] == width
            reason = "X é o menor eixo (#{(width*1000).round(2)}mm)"
          elsif smallest_dims[0] == height
            reason = "Y é o menor eixo (#{(height*1000).round(2)}mm)"
          else
            reason = "Z não é o menor eixo"
          end
          
          return {
            is_sheet: false,
            z_is_smallest: false,
            has_top_bottom_faces: nil,
            faces_are_coplanar: nil,
            dimensions: dimensions,
            thickness: depth,
            message: "Não é chapa: #{reason}"
          }
        end
        
        # 3. BUSCA TODAS AS FACES VOLTADAS PARA Z+ E Z-
        faces = definition.entities.grep(Sketchup::Face)
        
        if faces.empty?
          return {
            is_sheet: false,
            z_is_smallest: true,
            has_top_bottom_faces: false,
            faces_are_coplanar: nil,
            dimensions: dimensions,
            thickness: depth,
            message: "Nenhuma face encontrada no componente"
          }
        end
        
        # Encontra TODAS as faces voltadas para Z+ e Z-
        all_z_positive_faces = faces.select { |face| face.normal.z > 0.7 }
        all_z_negative_faces = faces.select { |face| face.normal.z < -0.7 }
        
        puts "DEBUG: #{all_z_positive_faces.length} face(s) Z+, #{all_z_negative_faces.length} face(s) Z-" if opts[:debug]
        
        if opts[:debug]
          puts "DEBUG: Faces Z+:"
          all_z_positive_faces.each_with_index do |face, i|
            face_z = get_face_z_position(face)
            puts "  #{i+1}. Área: #{(face.area * 1000000).round(0)}mm², Normal Z: #{face.normal.z.round(3)}, Z: #{(face_z*1000).round(2)}mm"
          end
          puts "DEBUG: Faces Z-:"
          all_z_negative_faces.each_with_index do |face, i|
            face_z = get_face_z_position(face)
            puts "  #{i+1}. Área: #{(face.area * 1000000).round(0)}mm², Normal Z: #{face.normal.z.round(3)}, Z: #{(face_z*1000).round(2)}mm"
          end
        end
        
        if all_z_positive_faces.empty? || all_z_negative_faces.empty?
          return {
            is_sheet: false,
            z_is_smallest: true,
            has_top_bottom_faces: false,
            faces_are_coplanar: nil,
            dimensions: dimensions,
            thickness: depth,
            message: "Faces superior ou inferior não encontradas"
          }
        end
        
        # 4. VERIFICA SE TODAS AS FACES Z+ SÃO COPLANARES ENTRE SI
        coplanar_result = check_all_faces_coplanar(all_z_positive_faces, all_z_negative_faces, opts)
        
        is_sheet = z_is_smallest && coplanar_result[:are_coplanar]
        
        # 5. CALCULA ÁREAS
        total_top_area = all_z_positive_faces.map(&:area).sum
        total_bottom_area = all_z_negative_faces.map(&:area).sum
        
        result = {
          is_sheet: is_sheet,
          z_is_smallest: z_is_smallest,
          has_top_bottom_faces: true,
          faces_are_coplanar: coplanar_result[:are_coplanar],
          dimensions: dimensions,
          thickness: depth,
          top_face_area: total_top_area,
          bottom_face_area: total_bottom_area,
          component_name: component_name
        }
        
        if is_sheet
          result[:message] = "✅ É uma chapa! Espessura: #{(depth*1000).round(2)}mm"
          puts "DEBUG: ✅ CONFIRMADO: Este componente É uma chapa!" if opts[:debug]
        else
          if !z_is_smallest
            result[:message] = "❌ Z não é o menor eixo"
          elsif !coplanar_result[:are_coplanar]
            result[:message] = "❌ #{coplanar_result[:message]}"
          else
            result[:message] = "❌ Falhou em critério não identificado"
          end
          puts "DEBUG: ❌ NÃO é uma chapa: #{result[:message]}" if opts[:debug]
        end
        
        return result
      end
      
      # Função para listar detalhes de componentes analisados
      def analyze_selection_detailed
        model = Sketchup.active_model
        selection = model.selection
        components = selection.select { |e| e.is_a?(Sketchup::ComponentInstance) }
        
        if components.empty?
          puts "=== ANÁLISE DETALHADA ==="
          puts "Nenhum componente selecionado"
          puts "========================="
          return
        end
        
        puts "\n=== ANÁLISE DETALHADA DE CHAPAS ==="
        puts "Componentes analisados: #{components.length}"
        
        results = detect_sheets(components, { debug: false, silent: true })
        sheet_results = results.is_a?(Hash) ? results[:results] : [results]
        
        sheet_results.each_with_index do |result, index|
          puts "\n#{index + 1}. #{result[:component_name]}"
          puts "   É chapa: #{result[:is_sheet] ? '✅ SIM' : '❌ NÃO'}"
          puts "   Dimensões: X=#{(result[:dimensions][:x]*1000).round(1)}mm, Y=#{(result[:dimensions][:y]*1000).round(1)}mm, Z=#{(result[:dimensions][:z]*1000).round(1)}mm"
          puts "   Z menor: #{result[:z_is_smallest]}"
          puts "   Tem faces sup/inf: #{result[:has_top_bottom_faces]}"
          puts "   Faces coplanares: #{result[:faces_are_coplanar]}"
          puts "   Razão: #{result[:message]}"
        end
        
        sheet_count = sheet_results.count { |r| r[:is_sheet] }
        puts "\n📊 RESUMO: #{sheet_count} de #{sheet_results.length} são chapas"
        puts "====================================="
        
        return results
      end
      
      private
      
      # NOVA FUNÇÃO: Verifica se todas as faces superiores são coplanares entre si
      # e se todas as faces inferiores são coplanares entre si
      def check_all_faces_coplanar(top_faces, bottom_faces, opts = {})
        tolerance = opts[:tolerance] || 0.0005
        
        puts "DEBUG: Verificando coplanaridade de #{top_faces.length} face(s) superior(es) e #{bottom_faces.length} face(s) inferior(es)..." if opts[:debug]
        
        # 1. VERIFICA SE TODAS AS FACES SUPERIORES SÃO COPLANARES ENTRE SI
        if top_faces.length > 1
          top_coplanar = check_faces_in_group_coplanar(top_faces, "superior", opts)
          if !top_coplanar[:are_coplanar]
            return {
              are_coplanar: false,
              message: "Faces superiores não são coplanares: #{top_coplanar[:message]}"
            }
          end
        end
        
        # 2. VERIFICA SE TODAS AS FACES INFERIORES SÃO COPLANARES ENTRE SI  
        if bottom_faces.length > 1
          bottom_coplanar = check_faces_in_group_coplanar(bottom_faces, "inferior", opts)
          if !bottom_coplanar[:are_coplanar]
            return {
              are_coplanar: false,
              message: "Faces inferiores não são coplanares: #{bottom_coplanar[:message]}"
            }
          end
        end
        
        # 3. VERIFICA SE AS FACES SUPERIORES E INFERIORES SÃO PARALELAS E SEPARADAS
        # Pega uma face de cada grupo para testar a separação
        sample_top = top_faces.first
        sample_bottom = bottom_faces.first
        
        separation_result = check_faces_parallel(sample_top, sample_bottom, opts)
        
        if !separation_result[:are_parallel]
          return {
            are_coplanar: false, 
            message: "Faces superior e inferior não são paralelas: #{separation_result[:message]}"
          }
        end
        
        puts "DEBUG: ✅ Todas as faces são coplanares adequadamente" if opts[:debug]
        
        return {
          are_coplanar: true,
          distance: separation_result[:distance],
          message: "Todas as faces superiores são coplanares, todas as inferiores são coplanares, e são paralelas entre si"
        }
      end
      
      # Verifica se um grupo de faces (todas do mesmo lado) são coplanares entre si
      def check_faces_in_group_coplanar(faces, side_name, opts = {})
        return { are_coplanar: true, message: "Apenas uma face" } if faces.length <= 1
        
        tolerance = opts[:tolerance] || 0.0005
        puts "DEBUG: Verificando coplanaridade entre #{faces.length} faces #{side_name}..." if opts[:debug]
        
        # Usa a primeira face como referência
        reference_face = faces.first
        reference_z = get_face_z_position(reference_face)
        
        # Verifica cada uma das outras faces
        faces[1..-1].each_with_index do |face, index|
          # 1. Verifica se as normais são paralelas
          dot_product = reference_face.normal.dot(face.normal).abs
          
          if dot_product < (1.0 - tolerance)
            return {
              are_coplanar: false,
              message: "Face #{index+2} tem normal diferente (produto escalar: #{dot_product.round(4)})"
            }
          end
          
          # 2. Verifica se estão no mesmo nível Z
          face_z = get_face_z_position(face)
          distance = (face_z - reference_z).abs
          
          puts "DEBUG: Face #{side_name} #{index+2}: diferença Z = #{(distance*1000).round(3)}mm" if opts[:debug]
          
          if distance > tolerance
            return {
              are_coplanar: false,
              message: "Face #{index+2} não está no mesmo plano (diferença Z: #{(distance*1000).round(1)}mm)"
            }
          end
        end
        
        puts "DEBUG: ✅ Todas as faces #{side_name} são coplanares" if opts[:debug]
        
        return {
          are_coplanar: true,
          message: "Todas as faces #{side_name} são coplanares"
        }
      end
      
      # Verifica se duas faces são paralelas
      def check_faces_parallel(top_face, bottom_face, opts = {})
        return { 
          are_parallel: false, 
          message: "Faces inválidas" 
        } unless top_face && bottom_face
        
        tolerance = opts[:tolerance] || 0.0005
        
        # Verifica se as normais são paralelas (ou anti-paralelas)
        top_normal = top_face.normal
        bottom_normal = bottom_face.normal
        
        # Produto escalar próximo de 1 ou -1 indica vetores paralelos
        dot_product = top_normal.dot(bottom_normal).abs
        
        puts "DEBUG: Produto escalar das normais: #{dot_product.round(4)} (deve ser ~1.0)" if opts[:debug]
        
        if dot_product < (1.0 - tolerance)
          return { 
            are_parallel: false, 
            message: "Faces não são paralelas (normais diferentes: #{dot_product.round(4)})" 
          }
        end
        
        # Calcula distância entre as faces
        top_z = get_face_z_position(top_face)
        bottom_z = get_face_z_position(bottom_face)
        distance = (top_z - bottom_z).abs
        
        return { 
          are_parallel: true, 
          distance: distance,
          message: "Faces são paralelas" 
        }
      end
      
      # Calcula bounding box do componente
      def get_component_bounds(definition)
        min_pt = nil
        max_pt = nil
        
        definition.entities.each do |entity|
          next unless entity.respond_to?(:bounds)
          
          entity_bounds = entity.bounds
          
          if min_pt.nil?
            min_pt = entity_bounds.min.clone
            max_pt = entity_bounds.max.clone
          else
            min_pt.x = [min_pt.x, entity_bounds.min.x].min
            min_pt.y = [min_pt.y, entity_bounds.min.y].min
            min_pt.z = [min_pt.z, entity_bounds.min.z].min
            
            max_pt.x = [max_pt.x, entity_bounds.max.x].max
            max_pt.y = [max_pt.y, entity_bounds.max.y].max
            max_pt.z = [max_pt.z, entity_bounds.max.z].max
          end
        end
        
        return nil if min_pt.nil?
        
        Geom::BoundingBox.new.tap do |bb|
          bb.add(min_pt)
          bb.add(max_pt)
        end
      end
      
      # Calcula posição Z média de uma face
      def get_face_z_position(face)
        vertices = face.vertices
        return 0 if vertices.empty?
        
        z_sum = vertices.map { |v| v.position.z }.sum
        z_sum / vertices.length.to_f
      end
    end
  end
end