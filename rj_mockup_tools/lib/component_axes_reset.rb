# encoding: UTF-8
# component_axes_reset.rb
# Módulo para resetar eixos de componentes, garantindo que Z seja o menor eixo

require 'sketchup.rb'

module Rjv
  module MockupTools
    module ComponentAxesReset
      extend self
      
      # Função principal para ser chamada por outras partes do projeto
      # Parâmetros:
      #   instances: Array de ComponentInstance ou ComponentInstance único
      #   options: Hash com opções (opcional)
      #     - max_attempts: número máximo de tentativas (padrão: 5)
      #     - tolerance: tolerância para comparações (padrão: 0.01)
      #     - silent: não mostra mensagens de UI (padrão: false)
      #     - debug: mostra mensagens de debug (padrão: true)
      #
      # Retorna: Hash com resultados
      #   - success: true/false
      #   - processed: número de componentes processados
      #   - failed: array com componentes que falharam
      #   - details: hash com detalhes de cada componente
      def reset_axes_to_smallest_z(instances, options = {})
        # Configurações padrão
        opts = {
          max_attempts: 5,
          tolerance: 0.01,
          silent: false,
          debug: true
        }.merge(options)
        
        # Normaliza entrada para array
        instances = [instances] unless instances.is_a?(Array)
        instances = instances.compact.select { |i| i.is_a?(Sketchup::ComponentInstance) }
        
        if instances.empty?
          return {
            success: false,
            processed: 0,
            failed: [],
            details: {},
            message: "Nenhum componente válido fornecido"
          }
        end
        
        model = instances.first.model
        processed = 0
        failed = []
        details = {}
        
        instances.each do |instance|
          result = reset_single_component_axes(instance, opts)
          
          if result[:success]
            processed += 1
          else
            failed << instance
          end
          
          details[instance.definition.name] = result
        end
        
        # Mensagem de resultado
        unless opts[:silent]
          if failed.empty?
            UI.messagebox("✅ #{processed} componente(s) tiveram seus eixos resetados com sucesso!")
          else
            UI.messagebox("⚠️ #{processed} componente(s) processados. #{failed.length} falharam.")
          end
        end
        
        {
          success: failed.empty?,
          processed: processed,
          failed: failed,
          details: details,
          message: "#{processed} processados, #{failed.length} falharam"
        }
      end
      
      # Função de conveniência para usar com seleção atual
      def run
        model = Sketchup.active_model
        selection = model.selection
        
        if selection.empty?
          UI.messagebox("Selecione os componentes para resetar os eixos.")
          return { success: false, message: "Nenhum componente selecionado" }
        end
        
        # Filtra apenas ComponentInstance
        components = selection.select { |e| e.is_a?(Sketchup::ComponentInstance) }
        
        if components.empty?
          UI.messagebox("Nenhum componente encontrado na seleção.")
          return { success: false, message: "Nenhum componente na seleção" }
        end
        
        return reset_axes_to_smallest_z(components)
      end
      
      # Função para resetar um único componente (uso interno)
      def reset_single_component_axes(instance, opts = {})
        return { success: false, message: "Instância inválida" } unless instance && instance.respond_to?(:definition)
        
        model = instance.model
        definition = instance.definition
        
        puts "\n=== RESETANDO EIXOS: #{definition.name} ===" if opts[:debug]
        
        # Verifica se há geometria suficiente
        edges = definition.entities.grep(Sketchup::Edge)
        if edges.length < 2
          msg = "Geometria insuficiente (menos de 2 arestas)"
          puts "DEBUG: #{msg}" if opts[:debug]
          return { success: false, message: msg }
        end
        
        # LOOP ATÉ Z SER O MENOR EIXO
        max_attempts = opts[:max_attempts] || 5
        attempt = 1
        
        model.start_operation("Resetar Eixos - #{definition.name}", true)
        
        begin
          while attempt <= max_attempts
            puts "\n--- TENTATIVA #{attempt} ---" if opts[:debug]
            
            # Verifica dimensões atuais
            current_bounds = get_current_bounds(definition)
            if current_bounds
              width = current_bounds.width
              height = current_bounds.height  
              depth = current_bounds.depth
              
              if opts[:debug]
                puts "DEBUG: Dimensões atuais - X: #{(width*1000).round(1)}mm, Y: #{(height*1000).round(1)}mm, Z: #{(depth*1000).round(1)}mm"
              end
              
              # Verifica se Z já é o menor
              if depth <= width && depth <= height
                puts "DEBUG: ✅ Z já é o menor eixo! Parando aqui." if opts[:debug]
                model.commit_operation
                return { 
                  success: true, 
                  attempts: attempt - 1,
                  final_dimensions: { x: width, y: height, z: depth },
                  message: "Z é o menor eixo após #{attempt - 1} tentativa(s)"
                }
              else
                if opts[:debug]
                  smallest_dim = [width, height, depth].min
                  if smallest_dim == width
                    puts "DEBUG: ❌ X é o menor (#{(width*1000).round(1)}mm), precisa virar Z"
                  elsif smallest_dim == height
                    puts "DEBUG: ❌ Y é o menor (#{(height*1000).round(1)}mm), precisa virar Z"
                  else
                    puts "DEBUG: ❌ Z não é o menor, continuando..."
                  end
                end
              end
            end
            
            # Calcula novos eixos baseados na geometria atual
            new_axes = get_new_axes(definition, opts)
            
            if new_axes.nil?
              msg = "Não foi possível calcular novos eixos na tentativa #{attempt}"
              puts "DEBUG: #{msg}" if opts[:debug]
              break
            end
            
            puts "DEBUG: Aplicando transformação da tentativa #{attempt}" if opts[:debug]
            
            # Aplica a transformação
            definition.entities.transform_entities(
              new_axes.inverse,
              definition.entities.to_a
            )
            
            # Ajusta as transformações de todas as instâncias
            definition.instances.each do |inst|
              inst.transformation = inst.transformation * new_axes
            end
            
            attempt += 1
          end
          
          # Se chegou aqui, não conseguiu em N tentativas
          puts "DEBUG: ⚠️  Não conseguiu fazer Z ser o menor eixo em #{max_attempts} tentativas" if opts[:debug]
          
          # Verifica dimensões finais
          final_bounds = get_current_bounds(definition)
          final_dims = nil
          if final_bounds
            width = final_bounds.width
            height = final_bounds.height  
            depth = final_bounds.depth
            final_dims = { x: width, y: height, z: depth }
            puts "DEBUG: Dimensões finais - X: #{(width*1000).round(1)}mm, Y: #{(height*1000).round(1)}mm, Z: #{(depth*1000).round(1)}mm" if opts[:debug]
          end
          
          model.commit_operation
          return { 
            success: false, 
            attempts: max_attempts,
            final_dimensions: final_dims,
            message: "Não conseguiu fazer Z ser o menor em #{max_attempts} tentativas"
          }
          
        rescue => e
          puts "ERROR: Erro ao resetar eixos: #{e.message}" if opts[:debug]
          model.abort_operation
          return { success: false, message: "Erro: #{e.message}" }
        end
      end
      
      private
      
      def get_new_axes(definition, opts = {})
        entities = definition.entities
        edges = entities.grep(Sketchup::Edge)
        
        # Coleta todos os vértices únicos
        pts = edges.flat_map(&:vertices).uniq.map(&:position)
        return nil if pts.empty?
        
        puts "DEBUG: Analisando #{pts.length} vértices e #{edges.length} arestas" if opts[:debug]
        
        # Determina nova origem baseada na geometria
        origin = get_new_origin(pts)
        puts "DEBUG: Nova origem calculada: #{origin}" if opts[:debug]
        
        # Encontra arestas conectadas à nova origem
        connected_edges = edges.select do |e|
          e.vertices.any? { |v| v.position.distance(origin) < 0.01 }  # tolerância maior: 1cm
        end
        
        puts "DEBUG: #{connected_edges.length} arestas conectadas à origem" if opts[:debug]
        
        if connected_edges.length < 2
          puts "DEBUG: Poucas arestas conectadas, usando método alternativo" if opts[:debug]
          return get_fallback_axes_with_z_check(origin, edges, definition, opts)
        end
        
        # Mapeia para pontos dos outros vértices
        other_pts = connected_edges.map do |e|
          vertices = e.vertices
          other_vertex = vertices.find { |v| v.position.distance(origin) >= 0.01 }
          other_vertex ? other_vertex.position : nil
        end.compact
        
        return nil if other_pts.length < 2
        
        # Converte para vetores normalizados
        vecs = other_pts.map { |pt| origin.vector_to(pt).normalize }
        
        # Mapeia de volta para pontos offset
        offset_pts = vecs.map { |vec| origin.offset(vec) }
        
        # Ordena por valor Z (menor primeiro)
        offset_pts.sort! { |a, b| a.z <=> b.z }
        
        # Mantém os 2 vetores com menores valores Z
        selected_vecs = vecs.select do |vec|
          offset_pts[0..1].any? { |pt| pt.distance(origin.offset(vec)) < 0.01 }
        end
        
        if selected_vecs.length < 2
          puts "DEBUG: Vetores insuficientes após filtragem Z" if opts[:debug]
          return get_fallback_axes_with_z_check(origin, edges, definition, opts)
        end
        
        # Ordena por ângulo com eixo X
        x_axis_ref = Geom::Vector3d.new(1, 0, 0)
        selected_vecs.sort! { |a, b| a.angle_between(x_axis_ref) <=> b.angle_between(x_axis_ref) }
        
        # Define eixos
        xaxis = selected_vecs.first
        
        # Z é perpendicular aos dois vetores
        zaxis = xaxis.cross(selected_vecs[1])
        
        # Se Z está apontando para baixo, inverte
        if zaxis.z < 0
          zaxis = zaxis.reverse
        end
        
        # Y é perpendicular a X e Z
        yaxis = zaxis.cross(xaxis)
        
        puts "DEBUG: Eixos iniciais - X: #{xaxis}, Y: #{yaxis}, Z: #{zaxis}" if opts[:debug]
        
        # REFINAMENTO: Garantir que Z seja o menor eixo
        final_axes = ensure_z_is_smallest_axis(origin, xaxis, yaxis, zaxis, definition)
        
        return final_axes
      end
      
      def get_new_origin(pts)
        # Ordena por valor Z (menor primeiro)
        pts.sort! { |a, b| a.z <=> b.z }
        
        # Mantém apenas pontos com Z mínimo
        z_min = pts.first.z
        pts.keep_if { |pt| (pt.z - z_min).abs < 0.01 }  # tolerância maior
        
        # Procura ponto mais próximo do eixo X (menor Y)
        pts.sort! { |a, b| a.y <=> b.y }
        y_min = pts.first.y
        pts.keep_if { |pt| (pt.y - y_min).abs < 0.01 }  # tolerância maior
        
        if pts.size == 1
          return pts.first
        else
          # Múltiplos pontos equidistantes, usa o mais à direita (maior X)
          pts.sort! { |a, b| a.x <=> b.x }
          return pts.last
        end
      end
      
      # Função para verificar dimensões atuais do componente
      def get_current_bounds(definition)
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
      
      # Versão do fallback que também verifica o Z menor
      def get_fallback_axes_with_z_check(origin, edges, definition, opts = {})
        puts "DEBUG: Usando método fallback para calcular eixos" if opts[:debug]
        
        # Método alternativo: usa as direções mais comuns das arestas
        directions = []
        
        edges.each do |edge|
          next if edge.length < 0.001  # ignora arestas muito pequenas
          
          dir = edge.line[1].normalize
          directions << dir
          directions << dir.reverse  # adiciona direção oposta também
        end
        
        return nil if directions.empty?
        
        # Agrupa direções similares
        grouped = group_similar_directions(directions)
        return nil if grouped.length < 2
        
        # Ordena por frequência
        grouped.sort! { |a, b| b[:count] <=> a[:count] }
        
        # Pega as duas direções mais comuns
        dir1 = grouped[0][:direction]
        dir2 = grouped[1][:direction]
        
        # Calcula Z como produto cruzado
        zaxis = dir1.cross(dir2)
        zaxis = zaxis.reverse if zaxis.z < 0  # garante que Z aponta para cima
        
        # Recalcula X e Y
        xaxis = dir1
        yaxis = zaxis.cross(xaxis)
        
        # Aplica verificação para garantir que Z seja o menor
        return ensure_z_is_smallest_axis(origin, xaxis, yaxis, zaxis, definition)
      end
      
      def group_similar_directions(directions)
        groups = []
        tolerance = 0.1  # ~6 graus
        
        directions.each do |direction|
          # Procura grupo existente
          existing_group = groups.find do |group|
            (group[:direction].dot(direction)).abs > (1 - tolerance)
          end
          
          if existing_group
            existing_group[:count] += 1
          else
            groups << { direction: direction, count: 1 }
          end
        end
        
        groups
      end
      
      # Nova função para garantir que Z seja o menor eixo
      def ensure_z_is_smallest_axis(origin, xaxis, yaxis, zaxis, definition)
        # Cria transformação temporária para testar as dimensões
        temp_transform = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
        
        # Calcula bounding box com os eixos atuais
        bounds = get_bounds_with_transform(definition, temp_transform)
        return nil unless bounds
        
        width = bounds.width   # dimensão X
        height = bounds.height # dimensão Y  
        depth = bounds.depth   # dimensão Z
        
        puts "DEBUG: Dimensões com eixos atuais - X: #{(width*1000).round(1)}mm, Y: #{(height*1000).round(1)}mm, Z: #{(depth*1000).round(1)}mm"
        
        # Verifica qual é a menor dimensão
        dimensions = [
          {size: width, axis: 'X', vector_x: xaxis, vector_y: yaxis, vector_z: zaxis},
          {size: height, axis: 'Y', vector_x: zaxis, vector_y: xaxis, vector_z: yaxis},
          {size: depth, axis: 'Z', vector_x: yaxis, vector_y: zaxis, vector_z: xaxis}
        ]
        
        # Ordena por tamanho (menor primeiro)
        dimensions.sort_by! { |d| d[:size] }
        smallest = dimensions.first
        
        puts "DEBUG: Menor dimensão é #{smallest[:axis]} (#{(smallest[:size]*1000).round(1)}mm)"
        
        if smallest[:axis] == 'Z'
          puts "DEBUG: Z já é o menor eixo - mantendo orientação atual"
          final_x, final_y, final_z = xaxis, yaxis, zaxis
        else
          puts "DEBUG: Reorientando para que Z seja o menor eixo (era #{smallest[:axis]})"
          final_x = smallest[:vector_x]
          final_y = smallest[:vector_y] 
          final_z = smallest[:vector_z]
        end
        
        puts "DEBUG: Eixos finais - X: #{final_x}, Y: #{final_y}, Z: #{final_z}"
        
        return Geom::Transformation.axes(origin, final_x, final_y, final_z)
      end
      
      # Calcula bounding box aplicando uma transformação
      def get_bounds_with_transform(definition, transform)
        return nil unless definition
        
        min_pt = nil
        max_pt = nil
        
        definition.entities.each do |entity|
          next unless entity.respond_to?(:bounds)
          
          entity_bounds = entity.bounds
          
          # Transforma os pontos do bounding box
          points = [
            entity_bounds.min,
            entity_bounds.max,
            Geom::Point3d.new(entity_bounds.min.x, entity_bounds.max.y, entity_bounds.min.z),
            Geom::Point3d.new(entity_bounds.max.x, entity_bounds.min.y, entity_bounds.min.z),
            Geom::Point3d.new(entity_bounds.min.x, entity_bounds.min.y, entity_bounds.max.z),
            Geom::Point3d.new(entity_bounds.max.x, entity_bounds.max.y, entity_bounds.min.z),
            Geom::Point3d.new(entity_bounds.min.x, entity_bounds.max.y, entity_bounds.max.z),
            Geom::Point3d.new(entity_bounds.max.x, entity_bounds.min.y, entity_bounds.max.z)
          ]
          
          points.each do |pt|
            transformed_pt = transform.inverse * pt
            
            if min_pt.nil?
              min_pt = transformed_pt.clone
              max_pt = transformed_pt.clone
            else
              min_pt.x = [min_pt.x, transformed_pt.x].min
              min_pt.y = [min_pt.y, transformed_pt.y].min
              min_pt.z = [min_pt.z, transformed_pt.z].min
              
              max_pt.x = [max_pt.x, transformed_pt.x].max
              max_pt.y = [max_pt.y, transformed_pt.y].max
              max_pt.z = [max_pt.z, transformed_pt.z].max
            end
          end
        end
        
        return nil if min_pt.nil?
        
        Geom::BoundingBox.new.tap do |bb|
          bb.add(min_pt)
          bb.add(max_pt)
        end
      end
      
      # Função para testar e visualizar antes de aplicar
      def analyze_component(instance)
        return unless instance && instance.respond_to?(:definition)
        
        definition = instance.definition
        edges = definition.entities.grep(Sketchup::Edge)
        pts = edges.flat_map(&:vertices).uniq.map(&:position)
        
        puts "\n=== ANÁLISE DO COMPONENTE #{definition.name} ==="
        puts "Vértices: #{pts.length}"
        puts "Arestas: #{edges.length}"
        
        if pts.any?
          origin = get_new_origin(pts)
          puts "Nova origem seria: #{origin}"
          
          # Mostra arestas conectadas
          connected = edges.select do |e|
            e.vertices.any? { |v| v.position.distance(origin) < 0.01 }
          end
          puts "Arestas conectadas à origem: #{connected.length}"
          
          connected.each_with_index do |edge, i|
            dir = edge.line[1]
            length = edge.length
            puts "  #{i+1}. Direção: #{dir}, Comprimento: #{(length * 1000).round(1)}mm"
          end
        end
        puts "================================\n"
      end
    end
  end
end