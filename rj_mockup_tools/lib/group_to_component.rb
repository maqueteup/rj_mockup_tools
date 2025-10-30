# encoding: UTF-8
# group_to_component.rb
# Módulo para converter grupos em componentes e opcionalmente resetar seus eixos

require 'sketchup.rb'

module Rjv
  module MockupTools
    module GroupToComponent
      extend self
      
      # Função principal para ser chamada por outras partes do projeto
      # Parâmetros:
      #   groups: Array de Group ou Group único, ou nil para usar seleção atual
      #   options: Hash com opções (opcional)
      #     - reset_axes: aplica reset de eixos após conversão (padrão: true)
      #     - axes_options: opções para o reset de eixos (padrão: {silent: true})
      #     - silent: não mostra mensagens de UI (padrão: false)
      #     - debug: mostra mensagens de debug (padrão: false)
      #
      # Retorna: Hash com resultados
      #   - success: true/false
      #   - converted: número de tipos de grupos convertidos
      #   - replaced: número de cópias substituídas
      #   - components: array com os componentes criados
      #   - axes_result: resultado do reset de eixos (se aplicado)
      #   - message: mensagem descritiva
      def convert_groups_to_components(groups = nil, options = {})
        # Configurações padrão
        opts = {
          reset_axes: true,
          axes_options: { silent: true, debug: false },
          silent: false,
          debug: false
        }.merge(options)
        
        model = Sketchup.active_model
        
        # Se não foram fornecidos grupos, usa a seleção atual
        if groups.nil?
          selection = model.selection
          groups = selection.grep(Sketchup::Group)
        else
          # Normaliza entrada para array
          groups = [groups] unless groups.is_a?(Array)
          groups = groups.compact.select { |g| g.is_a?(Sketchup::Group) }
        end
        
        if groups.empty?
          message = "Nenhum grupo válido encontrado para converter"
          UI.messagebox(message) unless opts[:silent]
          return {
            success: false,
            converted: 0,
            replaced: 0,
            components: [],
            axes_result: nil,
            message: message
          }
        end
        
        puts "DEBUG: Convertendo #{groups.length} grupo(s)..." if opts[:debug]
        
        model.start_operation("Converter Grupos em Componentes", true)
        
        begin
          # Agrupa os grupos selecionados por sua definição para processar cada tipo uma vez
          groups_by_definition = groups.group_by(&:definition)
          
          total_converted = 0
          total_replaced = 0
          created_components = []
          
          groups_by_definition.each_value do |groups_of_same_type|
            # Pega o primeiro grupo do tipo para converter
            pioneer_group = groups_of_same_type.first
            next unless pioneer_group.valid?
            
            original_definition = pioneer_group.definition
            original_name = pioneer_group.name
            
            puts "DEBUG: Convertendo grupo '#{original_name}'..." if opts[:debug]
            
            # --- Conversão Simples e Direta ---
            new_instance = pioneer_group.to_component
            new_component_definition = new_instance.definition
            new_component_definition.name = original_name unless original_name.to_s.empty?
            
            created_components << new_instance
            total_converted += 1
            
            # --- Busca e Substituição Recursiva ---
            copies_replaced_this_round = 0
            
            replace_copies_recursively = ->(entities_collection) do
              entities_collection.to_a.each do |entity|
                if entity.is_a?(Sketchup::Group) && entity.definition == original_definition
                  parent_entities = entity.parent.entities
                  transform = entity.transformation
                  new_copy = parent_entities.add_instance(new_component_definition, transform)
                  created_components << new_copy
                  entity.erase!
                  copies_replaced_this_round += 1
                elsif entity.is_a?(Sketchup::ComponentInstance)
                  replace_copies_recursively.call(entity.definition.entities)
                elsif entity.is_a?(Sketchup::Group)
                  replace_copies_recursively.call(entity.entities)
                end
              end
            end
            
            # Inicia a busca a partir da raiz do modelo
            replace_copies_recursively.call(model.entities)
            total_replaced += copies_replaced_this_round
            
            puts "DEBUG: Grupo '#{original_name}' - #{copies_replaced_this_round} cópias substituídas" if opts[:debug]
          end
          
          model.commit_operation
          
          # --- RESET DE EIXOS (SE HABILITADO) ---
          axes_result = nil
          if opts[:reset_axes] && !created_components.empty?
            puts "DEBUG: Aplicando reset de eixos nos componentes criados..." if opts[:debug]
            
            # Verifica se o módulo ComponentAxesReset está disponível
            if defined?(Rjv::MockupTools::ComponentAxesReset)
              axes_result = ComponentAxesReset.reset_axes_to_smallest_z(
                created_components,
                opts[:axes_options]
              )
              
              if opts[:debug]
                if axes_result[:success]
                  puts "DEBUG: ✅ Reset de eixos aplicado com sucesso em #{axes_result[:processed]} componente(s)"
                else
                  puts "DEBUG: ⚠️ Reset de eixos falhou: #{axes_result[:message]}"
                end
              end
            else
              puts "AVISO: Módulo ComponentAxesReset não encontrado - pulando reset de eixos" if opts[:debug]
              axes_result = { success: false, message: "Módulo ComponentAxesReset não disponível" }
            end
          end
          
          # --- Resultado Final ---
          message = "#{total_converted} tipo(s) de grupo convertido(s)"
          message += ", #{total_replaced} cópia(s) substituída(s)" if total_replaced > 0
          
          if axes_result && opts[:reset_axes]
            if axes_result[:success]
              message += ", eixos ajustados"
            else
              message += ", eixos NÃO ajustados"
            end
          end
          
          # Exibe mensagem (se não estiver em modo silencioso)
          unless opts[:silent]
            Sketchup.status_text = message
            puts message
          end
          
          {
            success: true,
            converted: total_converted,
            replaced: total_replaced,
            components: created_components,
            axes_result: axes_result,
            message: message
          }
          
        rescue => e
          model.abort_operation
          error_msg = "Erro durante conversão: #{e.message}"
          puts "ERROR: #{error_msg}" if opts[:debug]
          UI.messagebox(error_msg) unless opts[:silent]
          
          {
            success: false,
            converted: 0,
            replaced: 0,
            components: [],
            axes_result: nil,
            message: error_msg
          }
        end
      end
      
      # Função de conveniência para usar com seleção atual (mantém compatibilidade)
      def run
        result = convert_groups_to_components(
          nil, # usa seleção atual
          { 
            reset_axes: true,
            axes_options: { silent: true, debug: false },
            silent: false,
            debug: false
          }
        )
        
        # Exibe mensagem diferenciada para grupos vazios
        if !result[:success] && result[:converted] == 0
          UI.messagebox("Por favor, selecione um ou mais GRUPOS para converter. Componentes selecionados serão ignorados.")
        end
        
        return result
      end
      
      # Função de conveniência SEM reset de eixos
      def convert_groups_only(groups = nil, options = {})
        opts = { reset_axes: false }.merge(options)
        return convert_groups_to_components(groups, opts)
      end
      
      # Função de conveniência COM reset de eixos forçado
      def convert_groups_with_axes_reset(groups = nil, options = {})
        opts = { 
          reset_axes: true,
          axes_options: { silent: true, debug: false }
        }.merge(options)
        return convert_groups_to_components(groups, opts)
      end
      
      # Função para analisar grupos sem converter (útil para debug)
      def analyze_groups(groups = nil)
        model = Sketchup.active_model
        
        if groups.nil?
          selection = model.selection
          groups = selection.grep(Sketchup::Group)
        else
          groups = [groups] unless groups.is_a?(Array)
          groups = groups.compact.select { |g| g.is_a?(Sketchup::Group) }
        end
        
        if groups.empty?
          puts "=== ANÁLISE DE GRUPOS ==="
          puts "Nenhum grupo encontrado"
          puts "========================="
          return
        end
        
        groups_by_definition = groups.group_by(&:definition)
        
        puts "\n=== ANÁLISE DE GRUPOS ==="
        puts "Total de grupos selecionados: #{groups.length}"
        puts "Tipos únicos de grupos: #{groups_by_definition.keys.length}"
        
        groups_by_definition.each_with_index do |(definition, group_list), index|
          sample_group = group_list.first
          puts "\n#{index + 1}. Grupo: '#{sample_group.name}'"
          puts "   Instâncias: #{group_list.length}"
          puts "   Entidades: #{definition.entities.length}"
          
          if definition.entities.length > 0
            edges = definition.entities.grep(Sketchup::Edge)
            faces = definition.entities.grep(Sketchup::Face)
            puts "   Geometria: #{edges.length} arestas, #{faces.length} faces"
          end
        end
        puts "=========================\n"
        
        return {
          total_groups: groups.length,
          unique_types: groups_by_definition.keys.length,
          groups_by_definition: groups_by_definition
        }
      end
    end
  end
end