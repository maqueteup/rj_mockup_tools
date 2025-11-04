# encoding: UTF-8
# intelligent_workflow.rb
# Workflow inteligente simplificado - VERSÃO ESTÁVEL

require 'sketchup.rb'

module Rjv
  module MockupTools
    module IntelligentWorkflow
      extend self
      
      # Função principal que detecta a seleção e aplica o workflow adequado
      def run_intelligent_workflow(options = {})
        # Configurações padrão
        opts = {
          material_name: nil,
          thickness_mm: nil,
          reset_ucs: true,
          ucs_mode: :intelligent,
          silent: false,
          debug: false,
          material_auto_detect: true,
          strict_sheet_validation: true,
          sheet_tolerance: 0.0005,
          apply_material_to_non_sheets: false
        }.merge(options)
        
        model = Sketchup.active_model
        selection = model.selection
        
        puts "DEBUG: === INICIANDO WORKFLOW INTELIGENTE ===" if opts[:debug]
        puts "DEBUG: Seleção atual: #{selection.length} entidade(s)" if opts[:debug]
        
        # Detecta tipo de seleção e aplica workflow
        workflow_result = detect_and_execute_workflow(selection, opts)
        
        # Aplica material com validação
        if workflow_result[:success] && workflow_result[:target_components].any?
          puts "DEBUG: Aplicando material aos componentes resultantes..." if opts[:debug]
          
          if opts[:strict_sheet_validation]
            validated_result = validate_and_apply_material(
              workflow_result[:target_components], 
              opts
            )
            
            workflow_result[:validation_result] = validated_result
            workflow_result[:final_success] = validated_result[:success]
            workflow_result[:validated_sheets] = validated_result[:validated_sheets] || []
            workflow_result[:rejected_components] = validated_result[:rejected_components] || []
          else
            material_result = apply_material_to_components(
              workflow_result[:target_components], 
              opts
            )
            
            workflow_result[:material_result] = material_result
            workflow_result[:final_success] = material_result[:success]
          end
        else
          workflow_result[:material_result] = { success: false, message: "Nenhum componente para aplicar material" }
          workflow_result[:final_success] = false
        end
        
        # Mensagem final
        display_final_message(workflow_result, opts)
        
        puts "DEBUG: === WORKFLOW CONCLUÍDO ===" if opts[:debug]
        
        return workflow_result
      end
      
      # Funções de conveniência
      def run
        return run_intelligent_workflow({ debug: false, silent: false })
      end
      
      def run_strict(options = {})
        opts = { 
          strict_sheet_validation: true,
          apply_material_to_non_sheets: false,
          debug: false 
        }.merge(options)
        return run_intelligent_workflow(opts)
      end
      
      def run_permissive(options = {})
        opts = { 
          strict_sheet_validation: true,
          apply_material_to_non_sheets: true,
          debug: false 
        }.merge(options)
        return run_intelligent_workflow(opts)
      end
      
      def run_legacy(options = {})
        opts = { 
          strict_sheet_validation: false,
          debug: false 
        }.merge(options)
        return run_intelligent_workflow(opts)
      end
      
      def run_with_material(material_name, options = {})
        opts = { material_name: material_name }.merge(options)
        return run_intelligent_workflow(opts)
      end
      
      def run_silent(options = {})
        opts = { silent: true, debug: false }.merge(options)
        return run_intelligent_workflow(opts)
      end
      
      # Exibe mensagem final do resultado
      def display_final_message(result, opts)
        return if opts[:silent]
        
        # Para workflows simples (não mistos)
        if result[:workflow_type] != :mixed
          display_simple_workflow_message(result, opts)
        else
          # Para workflows mistos - mostra detalhes completos
          display_mixed_workflow_message(result, opts)
        end
      end
      
      # Mensagem para workflows simples
      def display_simple_workflow_message(result, opts)
        if result[:final_success]
          # SUCESSO - Status text + detalhes se necessário
          message_parts = []
          
          if result[:workflow_type]
            workflow_names = {
              drawing: "Ferramenta ativada",
              faces: "Placas criadas", 
              groups: "Componentes convertidos",
              components: "Componentes processados"
            }
            message_parts << workflow_names[result[:workflow_type]]
          end
          
          # Material aplicado
          if result[:validation_result] && result[:validation_result][:material_applied]
            message_parts << "Material #{result[:validation_result][:material_applied]} aplicado"
          elsif result[:material_result] && result[:material_result][:material_applied]
            message_parts << "Material #{result[:material_result][:material_applied]} aplicado"
          end
          
          # Validação
          if result[:validated_sheets] && result[:validated_sheets].any?
            message_parts << "#{result[:validated_sheets].length} chapas validadas"
          end
          
          success_message = "✅ " + message_parts.join(" | ")
          Sketchup.status_text = success_message
          
          # Se há rejeições, sempre mostra ao usuário
          if result[:rejected_components] && result[:rejected_components].any?
            show_rejection_dialog(result[:validation_result][:rejection_details] || {})
          end
          
        else
          # FALHA - Messagebox detalhado
          error_message = "❌ Workflow falhou"
          
          if result[:validation_result] && result[:validation_result][:message]
            error_message += "\n\n#{result[:validation_result][:message]}"
          elsif result[:message] && !result[:message].empty?
            error_message += "\n\n#{result[:message]}"
          end
          
          # Adiciona detalhes de material se houver
          if result[:material_result] && !result[:material_result][:success] && result[:material_result][:message]
            error_message += "\n\nMaterial: #{result[:material_result][:message]}"
          end
          
          # Adiciona detalhes de rejeições
          if result[:validation_result] && result[:validation_result][:rejection_details] && result[:validation_result][:rejection_details].any?
            error_message += "\n\n--- Detalhes das Rejeições ---"
            result[:validation_result][:rejection_details].each do |name, reason|
              error_message += "\n• #{name}: #{reason}"
            end
          end
          
          UI.messagebox(error_message, MB_OK, "Erro no Workflow")
        end
      end
      
      # Mensagem detalhada para workflows mistos
      def display_mixed_workflow_message(result, opts)
        # Monta relatório completo do workflow misto
        report_lines = ["=== RELATÓRIO DE CONVERSÃO MISTA ===", ""]
        
        success_count = 0
        error_count = 0
        
        # Analisa resultados de cada tipo
        if result[:step_results][:faces]
          face_result = result[:step_results][:faces]
          if face_result[:success]
            report_lines << "✅ FACES → PLACAS: #{face_result[:target_components].length} placa(s) criada(s)"
            success_count += 1
          else
            report_lines << "❌ FACES: #{face_result[:message]}"
            error_count += 1
          end
        end
        
        if result[:step_results][:groups]
          group_result = result[:step_results][:groups]
          if group_result[:success]
            report_lines << "✅ GRUPOS → COMPONENTES: #{group_result[:target_components].length} componente(s) criado(s)"
            success_count += 1
          else
            report_lines << "❌ GRUPOS: #{group_result[:message]}"
            error_count += 1
          end
        end
        
        if result[:step_results][:components]
          comp_result = result[:step_results][:components]
          if comp_result[:success]
            report_lines << "✅ COMPONENTES: #{comp_result[:target_components].length} componente(s) processado(s)"
            success_count += 1
          else
            report_lines << "❌ COMPONENTES: #{comp_result[:message]}"
            error_count += 1
          end
        end
        
        # Adiciona linha separadora
        report_lines << ""
        
        # Resultado da aplicação de material
        if result[:final_success]
          if result[:validation_result] && result[:validation_result][:material_applied]
            report_lines << "✅ MATERIAL: #{result[:validation_result][:material_applied]} aplicado"
            
            # Detalhes de validação
            if result[:validated_sheets] && result[:validated_sheets].any?
              report_lines << "   → #{result[:validated_sheets].length} chapa(s) validada(s)"
            end
            
            if result[:rejected_components] && result[:rejected_components].any?
              report_lines << "   → #{result[:rejected_components].length} componente(s) rejeitado(s)"
              report_lines << ""
              report_lines << "--- COMPONENTES REJEITADOS ---"
              
              if result[:validation_result][:rejection_details]
                result[:validation_result][:rejection_details].each do |name, reason|
                  report_lines << "• #{name}: #{reason}"
                end
              end
            end
            
          elsif result[:material_result] && result[:material_result][:material_applied]
            report_lines << "✅ MATERIAL: #{result[:material_result][:material_applied]} aplicado a todos"
          end
        else
          if result[:validation_result] && result[:validation_result][:message]
            report_lines << "❌ MATERIAL: #{result[:validation_result][:message]}"
          elsif result[:material_result] && result[:material_result][:message]
            report_lines << "❌ MATERIAL: #{result[:material_result][:message]}"
          end
        end
        
        # Resumo final
        report_lines << ""
        report_lines << "=== RESUMO ==="
        report_lines << "Operações bem-sucedidas: #{success_count}"
        report_lines << "Operações com erro: #{error_count}"
        
        if result[:final_success]
          report_lines << "Material: APLICADO ✅"
          status_msg = "✅ Conversão mista: #{success_count}/#{success_count + error_count} sucessos"
        else
          report_lines << "Material: FALHOU ❌"
          status_msg = "⚠️ Conversão mista: #{success_count}/#{success_count + error_count} sucessos - Material falhou"
        end
        
        # Mostra no status
        Sketchup.status_text = status_msg
        
        # Mostra relatório completo em messagebox
        UI.messagebox(report_lines.join("\n"), MB_OK, "Relatório de Conversão Mista")
      end
      
      # Mostra detalhes de rejeições em messagebox - MELHORADO
      def show_rejection_dialog(rejection_details)
        return if rejection_details.empty?
        
        # Sempre mostra detalhes, independente da quantidade
        detail_lines = rejection_details.map do |component_name, reason|
          "• #{component_name}: #{reason}"
        end
        
        message = "⚠️ COMPONENTES NÃO VALIDADOS COMO CHAPAS:\n\n"
        message += detail_lines.join("\n")
        message += "\n\n💡 Apenas chapas válidas receberam material."
        message += "\n\nPara aplicar material a todos os componentes, use o modo permissivo:"
        message += "\nRjv::MockupTools::IntelligentWorkflow.run_permissive"
        
        UI.messagebox(message, MB_OK, "Validação de Chapas")
      end
      
      # Validação e aplicação de material
      def validate_and_apply_material(components, opts)
        if components.empty?
          return { 
            success: false, 
            message: "Nenhum componente para validar" 
          }
        end
        
        begin
          puts "DEBUG: Validando #{components.length} componente(s) como chapas..." if opts[:debug]
          
          # 1. VALIDAÇÃO DE CHAPAS usando SheetDetector
          if defined?(Rjv::MockupTools::SheetDetector)
            validation_result = validate_components_as_sheets(components, opts)
            
            valid_sheets = validation_result[:valid_sheets]
            rejected_components = validation_result[:rejected_components]
            
            puts "DEBUG: Validação concluída - #{valid_sheets.length} chapas válidas, #{rejected_components.length} rejeitadas" if opts[:debug]
            
            # Decide quais componentes recebem material
            if opts[:apply_material_to_non_sheets]
              material_targets = components
              puts "DEBUG: Modo permissivo - aplicando material a todos os componentes" if opts[:debug]
            else
              material_targets = valid_sheets
              puts "DEBUG: Modo rigoroso - aplicando material apenas a chapas validadas" if opts[:debug]
            end
            
            # Se não há chapas válidas no modo rigoroso
            if material_targets.empty? && !opts[:apply_material_to_non_sheets]
              return {
                success: false,
                validated_sheets: [],
                rejected_components: components,
                message: "Nenhum componente válido como chapa encontrado. #{components.length} componente(s) rejeitado(s).",
                rejection_details: validation_result[:rejection_details]
              }
            end
            
          else
            # Sem SheetDetector - aceita todos com aviso
            puts "DEBUG: SheetDetector não disponível - aceitando todos os componentes" if opts[:debug]
            material_targets = components
            valid_sheets = components
            rejected_components = []
            validation_result = { rejection_details: {} }
          end
          
          # 2. APLICAÇÃO DE MATERIAL
          if material_targets.any?
            material_result = apply_material_to_validated_components(material_targets, opts)
            
            return {
              success: material_result[:success],
              validated_sheets: valid_sheets,
              rejected_components: rejected_components,
              material_applied: material_result[:material_applied],
              components_with_material: material_targets.length,
              message: build_validation_message(valid_sheets, rejected_components, material_result),
              material_result: material_result,
              rejection_details: validation_result[:rejection_details]
            }
          else
            return {
              success: false,
              validated_sheets: valid_sheets,
              rejected_components: rejected_components,
              message: "Nenhum componente para aplicar material"
            }
          end
          
        rescue => e
          puts "DEBUG: Erro na validação: #{e.message}" if opts[:debug]
          return { 
            success: false, 
            message: "Erro na validação de chapas: #{e.message}" 
          }
        end
      end
      
      # Valida componentes usando SheetDetector
      def validate_components_as_sheets(components, opts)
        unless defined?(Rjv::MockupTools::SheetDetector)
          return {
            valid_sheets: [],
            rejected_components: components,
            rejection_details: {}
          }
        end
        
        valid_sheets = []
        rejected_components = []
        rejection_details = {}
        
        components.each do |component|
          begin
            detection_result = Rjv::MockupTools::SheetDetector.analyze_single_component(
              component, 
              {
                tolerance: opts[:sheet_tolerance],
                debug: false,
                silent: true
              }
            )
            
            if detection_result[:is_sheet]
              valid_sheets << component
              puts "DEBUG: ✅ #{detection_result[:component_name]} validado como chapa (#{(detection_result[:thickness]*1000).round(1)}mm)" if opts[:debug]
            else
              rejected_components << component
              rejection_details[component.definition.name] = detection_result[:message]
              puts "DEBUG: ❌ #{detection_result[:component_name]} rejeitado: #{detection_result[:message]}" if opts[:debug]
            end
            
          rescue => e
            rejected_components << component
            rejection_details[component.definition.name] = "Erro na validação: #{e.message}"
            puts "DEBUG: ❌ Erro ao validar #{component.definition.name}: #{e.message}" if opts[:debug]
          end
        end
        
        return {
          valid_sheets: valid_sheets,
          rejected_components: rejected_components,
          rejection_details: rejection_details
        }
      end
      
      # Aplica material apenas a componentes já validados
      def apply_material_to_validated_components(components, opts)
        if components.empty?
          return { success: false, message: "Nenhum componente validado" }
        end
        
        begin
          puts "DEBUG: Aplicando material a #{components.length} componente(s) validado(s)..." if opts[:debug]
          
          # Detecta ou solicita material
          material_to_apply = get_material_for_application(components, opts)
          
          unless material_to_apply
            return { success: false, message: "Nenhum material selecionado" }
          end
          
          puts "DEBUG: Material selecionado: #{material_to_apply[:name]}" if opts[:debug]
          
          # Aplica material
          model = components.first.model
          original_selection = model.selection.to_a
          
          begin
            model.selection.clear
            model.selection.add(components)
            
            if defined?(Rjv::MockupTools::MaterialSystem)
              MaterialSystem.execute_material_action(material_to_apply)
              
              return {
                success: true,
                material_applied: material_to_apply[:name],
                components_count: components.length,
                message: "Material '#{material_to_apply[:name]}' aplicado a #{components.length} chapa(s) validada(s)"
              }
            else
              return { success: false, message: "Sistema de materiais não disponível" }
            end
            
          ensure
            model.selection.clear
            model.selection.add(original_selection) if original_selection.any?
          end
          
        rescue => e
          return { 
            success: false, 
            message: "Erro ao aplicar material: #{e.message}" 
          }
        end
      end
      
      # Constrói mensagem detalhada de validação
      def build_validation_message(valid_sheets, rejected_components, material_result)
        parts = []
        
        if valid_sheets.any?
          parts << "#{valid_sheets.length} chapa(s) validada(s)"
        end
        
        if rejected_components.any?
          parts << "#{rejected_components.length} componente(s) rejeitado(s)"
        end
        
        if material_result[:success]
          parts << "Material aplicado com sucesso"
        elsif material_result[:message]
          parts << "Erro no material: #{material_result[:message]}"
        end
        
        return parts.join(", ")
      end
      
      private
      
      # Detecta tipo de seleção e executa workflow apropriado
      def detect_and_execute_workflow(selection, opts)
        faces = selection.grep(Sketchup::Face).select(&:valid?)
        groups = selection.grep(Sketchup::Group)
        components = selection.grep(Sketchup::ComponentInstance)
        
        puts "DEBUG: Detectado - Faces: #{faces.length}, Grupos: #{groups.length}, Componentes: #{components.length}" if opts[:debug]
        
        # SELEÇÃO VAZIA → Ferramenta de desenho
        if selection.empty?
          puts "DEBUG: Seleção vazia - iniciando ferramenta de desenho" if opts[:debug]
          return execute_drawing_workflow(opts)
          
        # FACES SELECIONADAS → Face to Board
        elsif faces.any? && groups.empty? && components.empty?
          puts "DEBUG: Faces detectadas - executando Face to Board" if opts[:debug]
          return execute_face_workflow(faces, opts)
          
        # GRUPOS SELECIONADOS → Group to Component
        elsif groups.any? && faces.empty? && components.empty?
          puts "DEBUG: Grupos detectados - executando Group to Component" if opts[:debug]
          return execute_group_workflow(groups, opts)
          
        # COMPONENTES SELECIONADOS → Reset Axes
        elsif components.any? && faces.empty? && groups.empty?
          puts "DEBUG: Componentes detectados - executando Component workflow" if opts[:debug]
          return execute_component_workflow(components, opts)
          
        # SELEÇÃO MISTA → Processa cada tipo separadamente
        else
          puts "DEBUG: Seleção mista - processando cada tipo" if opts[:debug]
          return execute_mixed_workflow(faces, groups, components, opts)
        end
      end
      
      # WORKFLOW: Ferramenta de desenho
      def execute_drawing_workflow(opts)
        result = {
          success: false,
          workflow_type: :drawing,
          target_components: [],
          steps_executed: [],
          step_results: {},
          message: "Aguardando criação de face..."
        }
        
        begin
          puts "DEBUG: Iniciando ferramenta de retângulo..." if opts[:debug]
          
          # Ativa ferramenta de desenho
          if defined?(Rjv::MockupTools::Rectangle3Points)
            Rectangle3Points.start_tool
          else
            Sketchup.send_action("selectRectangleTool:")
          end
          
          result[:success] = true
          result[:message] = "Ferramenta ativada"
          result[:steps_executed] = ["drawing_tool_started"]
          
          # Mensagem para o usuário
          unless opts[:silent]
            material_hint = opts[:material_name] ? " em #{opts[:material_name]}" : ""
            UI.messagebox("🎯 Ferramenta de retângulo ativada!\n\n1. Desenhe uma face\n2. Clique novamente no material para converter em placa#{material_hint}\n\n(Alternativamente, selecione a face e clique no material)", MB_OK, "Workflow Ativado")
          end
          
        rescue => e
          result[:message] = "Erro ao iniciar ferramenta de desenho: #{e.message}"
          puts "DEBUG: #{result[:message]}" if opts[:debug]
        end
        
        return result
      end
      
      # Workflow para faces (Face to Board) - COM DETALHES DE ERRO
      def execute_face_workflow(faces, opts)
        result = {
          success: false,
          workflow_type: :faces,
          target_components: [],
          steps_executed: [],
          step_results: {},
          message: ""
        }
        
        begin
          puts "DEBUG: Executando Face to Board em #{faces.length} face(s)..." if opts[:debug]
          
          # Status simples
          Sketchup.status_text = "Criando placa(s)..."
          
          if defined?(Rjv::MockupTools::FaceToBoard) && 
             FaceToBoard.respond_to?(:create_boards_from_faces)
            
            face_result = FaceToBoard.create_boards_from_faces(
              faces,
              {
                thickness_mm: opts[:thickness_mm],
                reset_ucs: opts[:reset_ucs],
                ucs_mode: opts[:ucs_mode],
                silent: true,
                debug: opts[:debug]
              }
            )
            
          else
            # Fallback para versão original
            puts "DEBUG: Usando Face to Board original" if opts[:debug]
            
            model = faces.first.model
            original_selection = model.selection.to_a
            
            begin
              model.selection.clear
              model.selection.add(faces)
              
              FaceToBoard.run
              
              created_components = model.entities.grep(Sketchup::ComponentInstance).select do |comp|
                comp.definition.name.include?("Placa_")
              end
              
              face_result = {
                success: !created_components.empty?,
                created_components: created_components,
                message: created_components.empty? ? "Nenhuma placa foi criada" : "#{created_components.length} placa(s) criada(s)"
              }
              
            ensure
              model.selection.clear
              model.selection.add(original_selection) if original_selection.any?
            end
          end
          
          result[:steps_executed] << "face_to_board"
          result[:step_results][:face_to_board] = face_result
          
          if face_result[:success]
            result[:target_components] = face_result[:created_components]
            result[:success] = true
            result[:message] = "#{face_result[:created_components].length} placa(s) criada(s)"
            
            puts "DEBUG: ✅ Face to Board concluído" if opts[:debug]
          else
            result[:message] = "Face to Board falhou: #{face_result[:message] || 'Erro desconhecido'}"
            puts "DEBUG: ❌ Face to Board falhou: #{face_result[:message]}" if opts[:debug]
          end
          
        rescue => e
          result[:message] = "Erro no workflow de faces: #{e.message}"
          puts "DEBUG: ❌ #{result[:message]}" if opts[:debug]
        end
        
        return result
      end
      
      # Workflow para grupos - COM DETALHES DE ERRO
      def execute_group_workflow(groups, opts)
        result = {
          success: false,
          workflow_type: :groups,
          target_components: [],
          steps_executed: [],
          step_results: {},
          message: ""
        }
        
        begin
          puts "DEBUG: Executando Group to Component em #{groups.length} grupo(s)..." if opts[:debug]
          
          Sketchup.status_text = "Convertendo grupos..."
          
          if defined?(Rjv::MockupTools::GroupToComponent)
            group_result = GroupToComponent.convert_groups_to_components(
              groups,
              {
                reset_axes: false,
                silent: true,
                debug: opts[:debug]
              }
            )
            
            result[:steps_executed] << "group_to_component"
            result[:step_results][:group_to_component] = group_result
            
            if group_result[:success]
              created_components = group_result[:components]
              puts "DEBUG: ✅ Group to Component criou #{created_components.length} componente(s)" if opts[:debug]
              
              # Reset de eixos se necessário
              if opts[:reset_ucs] && defined?(Rjv::MockupTools::ComponentAxesReset)
                puts "DEBUG: Aplicando Component Axes Reset..." if opts[:debug]
                
                axes_result = ComponentAxesReset.reset_axes_to_smallest_z(
                  created_components,
                  {
                    silent: true,
                    debug: opts[:debug]
                  }
                )
                
                result[:steps_executed] << "component_axes_reset"
                result[:step_results][:component_axes_reset] = axes_result
                
                # Se reset de eixos falhou, adiciona ao relatório
                unless axes_result[:success]
                  result[:message] += " (Aviso: Reset de eixos falhou: #{axes_result[:message]})"
                end
              end
              
              result[:target_components] = created_components
              result[:success] = true
              result[:message] = "#{created_components.length} componente(s) criado(s)"
              
            else
              result[:message] = "Group to Component falhou: #{group_result[:message] || 'Erro desconhecido'}"
            end
          else
            result[:message] = "Módulo GroupToComponent não disponível - Instale a extensão Group to Component"
          end
          
        rescue => e
          result[:message] = "Erro no workflow de grupos: #{e.message}"
        end
        
        return result
      end
      
      # Workflow para componentes
      def execute_component_workflow(components, opts)
        result = {
          success: false,
          workflow_type: :components,
          target_components: [],
          steps_executed: [],
          step_results: {},
          message: ""
        }
        
        begin
          puts "DEBUG: Executando Component workflow em #{components.length} componente(s)..." if opts[:debug]
          
          Sketchup.status_text = "Processando componentes..."
          
          # Reset Axes se necessário
          if opts[:reset_ucs] && defined?(Rjv::MockupTools::ComponentAxesReset)
            axes_result = ComponentAxesReset.reset_axes_to_smallest_z(
              components,
              {
                silent: true,
                debug: opts[:debug]
              }
            )
            
            result[:steps_executed] << "reset_axes"
            result[:step_results][:reset_axes] = axes_result
          end
          
          result[:target_components] = components
          result[:success] = true
          result[:message] = "#{components.length} componente(s) processado(s)"
          
        rescue => e
          result[:message] = "Erro no workflow de componentes: #{e.message}"
        end
        
        return result
      end
      
      # Workflow para seleção mista
      def execute_mixed_workflow(faces, groups, components, opts)
        result = {
          success: false,
          workflow_type: :mixed,
          target_components: [],
          steps_executed: [],
          step_results: {},
          message: ""
        }
        
        all_components = []
        messages = []
        
        begin
          puts "DEBUG: Executando workflow misto..." if opts[:debug]
          
          Sketchup.status_text = "Processando seleção mista..."
          
          # Processa cada tipo silenciosamente
          silent_opts = opts.merge(silent: true)
          
          if faces.any?
            face_result = execute_face_workflow(faces, silent_opts)
            result[:step_results][:faces] = face_result
            
            if face_result[:success]
              all_components.concat(face_result[:target_components])
              result[:steps_executed] << "faces_processed"
              messages << "#{face_result[:target_components].length} placa(s)"
            end
          end
          
          if groups.any?
            group_result = execute_group_workflow(groups, silent_opts)
            result[:step_results][:groups] = group_result
            
            if group_result[:success]
              all_components.concat(group_result[:target_components])
              result[:steps_executed] << "groups_processed"
              messages << "#{group_result[:target_components].length} de grupos"
            end
          end
          
          if components.any?
            component_result = execute_component_workflow(components, silent_opts)
            result[:step_results][:components] = component_result
            
            if component_result[:success]
              all_components.concat(component_result[:target_components])
              result[:steps_executed] << "components_processed"
              messages << "#{component_result[:target_components].length} processados"
            end
          end
          
          result[:target_components] = all_components.uniq
          result[:success] = all_components.any?
          result[:message] = messages.join(", ")
          
        rescue => e
          result[:message] = "Erro no workflow misto: #{e.message}"
        end
        
        return result
      end
      
      # Aplica material aos componentes (VERSÃO ORIGINAL - sem validação)
      def apply_material_to_components(components, opts)
        if components.empty?
          return { success: false, message: "Nenhum componente para processar" }
        end
        
        begin
          puts "DEBUG: Aplicando material a #{components.length} componente(s)..." if opts[:debug]
          
          material_to_apply = get_material_for_application(components, opts)
          
          unless material_to_apply
            return { success: false, message: "Nenhum material selecionado" }
          end
          
          puts "DEBUG: Material selecionado: #{material_to_apply[:name]}" if opts[:debug]
          
          model = components.first.model
          original_selection = model.selection.to_a
          
          begin
            model.selection.clear
            model.selection.add(components)
            
            if defined?(Rjv::MockupTools::MaterialSystem)
              MaterialSystem.execute_material_action(material_to_apply)
              
              return {
                success: true,
                material_applied: material_to_apply[:name],
                components_count: components.length,
                message: "Material '#{material_to_apply[:name]}' aplicado a #{components.length} componente(s)"
              }
            else
              return { success: false, message: "Sistema de materiais não disponível" }
            end
            
          ensure
            model.selection.clear
            model.selection.add(original_selection) if original_selection.any?
          end
          
        rescue => e
          return { 
            success: false, 
            message: "Erro ao aplicar material: #{e.message}" 
          }
        end
      end
      
      # Detecta ou solicita material para aplicação
      def get_material_for_application(components, opts)
        # Se material foi especificado nas opções
        if opts[:material_name]
          puts "DEBUG: Usando material especificado: #{opts[:material_name]}" if opts[:debug]
          return find_material_by_name(opts[:material_name])
        end
        
        # Se auto-detecção está habilitada
        if opts[:material_auto_detect] && defined?(Rjv::MockupTools::MaterialSystem)
          puts "DEBUG: Tentando auto-detecção de material..." if opts[:debug]
          
          grouped_materials = MaterialSystem.get_grouped_materials_for_selector
          
          if grouped_materials.keys.length == 1
            type_name = grouped_materials.keys.first
            first_thickness = grouped_materials[type_name][:thicknesses].first
            
            if first_thickness
              material = find_material_by_full_name(first_thickness[:full_name])
              if material
                puts "DEBUG: Auto-detectado material único: #{material[:name]}" if opts[:debug]
                return material
              end
            end
          end
        end
        
        # Se não conseguiu detectar e não está em modo silencioso, pergunta ao usuário
        unless opts[:silent]
          puts "DEBUG: Solicitando seleção de material ao usuário..." if opts[:debug]
          return prompt_user_for_material()
        end
        
        puts "DEBUG: Nenhum material determinado" if opts[:debug]
        return nil
      end
      
      # Encontra material por nome
      def find_material_by_name(name)
        return nil unless defined?(Rjv::MockupTools::MaterialSystem)
        
        all_materials = MaterialSystem.property_manager.properties[:materials] || []
        all_materials.find do |m|
          m[:name] == name && m[:active]
        end
      end
      
      # Encontra material por nome completo
      def find_material_by_full_name(full_name)
        return nil unless defined?(Rjv::MockupTools::MaterialSystem)
        
        all_materials = MaterialSystem.property_manager.properties[:materials] || []
        all_materials.find do |m|
          m[:name] == full_name && m[:active]
        end
      end
      
      # Solicita material ao usuário
      def prompt_user_for_material
        return nil unless defined?(Rjv::MockupTools::MaterialSystem)
        
        all_materials = MaterialSystem.property_manager.properties[:materials] || []
        active_materials = all_materials.select do |m|
          m[:active]
        end
        
        return nil if active_materials.empty?
        
        material_names = active_materials.map do |m|
          m[:name]
        end
        
        result = UI.inputbox(
          ["Selecione o material:"],
          [material_names.first],
          [material_names.join("|")],
          "Seleção de Material"
        )
        
        return nil unless result
        
        selected_name = result[0]
        return active_materials.find do |m|
          m[:name] == selected_name
        end
      end
      
      # Funções de análise (mantidas para compatibilidade)
      def analyze_current_selection_with_validation
        model = Sketchup.active_model
        selection = model.selection
        
        faces = selection.grep(Sketchup::Face).select(&:valid?)
        groups = selection.grep(Sketchup::Group)
        components = selection.grep(Sketchup::ComponentInstance)
        
        puts "\n=== ANÁLISE DETALHADA COM VALIDAÇÃO ==="
        puts "Seleção atual: #{selection.length} entidade(s)"
        puts "• Faces: #{faces.length}"
        puts "• Grupos: #{groups.length}"  
        puts "• Componentes: #{components.length}"
        
        if components.any? && defined?(Rjv::MockupTools::SheetDetector)
          puts "\n--- VALIDAÇÃO DE CHAPAS NOS COMPONENTES ---"
          
          components.each_with_index do |comp, i|
            result = Rjv::MockupTools::SheetDetector.analyze_single_component(
              comp, { debug: false, silent: true }
            )
            
            status = result[:is_sheet] ? "✅ CHAPA" : "❌ NÃO-CHAPA"
            thickness = result[:thickness] ? "(#{(result[:thickness]*1000).round(1)}mm)" : ""
            
            puts "  #{i+1}. #{comp.definition.name}: #{status} #{thickness}"
            puts "     → #{result[:message]}" unless result[:is_sheet]
          end
        end
        
        puts "========================================\n"
        
        return {
          faces: faces.length,
          groups: groups.length,
          components: components.length,
          workflow_type: determine_workflow_type(faces, groups, components)
        }
      end
      
      def validate_selection_as_sheets(show_ui = true)
        model = Sketchup.active_model
        selection = model.selection
        components = selection.select do |e|
          e.is_a?(Sketchup::ComponentInstance)
        end
        
        if components.empty?
          message = "Nenhum componente selecionado para validar"
          UI.messagebox(message) if show_ui
          return { success: false, message: message }
        end
        
        result = validate_components_as_sheets(
          components, 
          { 
            debug: true, 
            silent: false,
            sheet_tolerance: 0.0005 
          }
        )
        
        if show_ui
          if result[:valid_sheets].any?
            valid_names = result[:valid_sheets].map do |c|
              c.definition.name
            end.join(", ")
            message = "✅ #{result[:valid_sheets].length} chapa(s) válida(s):\n#{valid_names}"
            
            if result[:rejected_components].any?
              rejected_details = result[:rejection_details].map do |name, reason|
                "• #{name}: #{reason}"
              end
              message += "\n\n❌ #{result[:rejected_components].length} rejeitada(s):\n" + rejected_details.join("\n")
            end
          else
            rejected_details = result[:rejection_details].map do |name, reason|
              "• #{name}: #{reason}"
            end
            message = "❌ Nenhuma chapa válida encontrada.\n\nMotivos:\n" + rejected_details.join("\n")
          end
          
          UI.messagebox(message)
        end
        
        return {
          success: result[:valid_sheets].any?,
          valid_sheets: result[:valid_sheets],
          rejected_components: result[:rejected_components],
          rejection_details: result[:rejection_details]
        }
      end
      
      def analyze_current_selection
        model = Sketchup.active_model
        selection = model.selection
        
        faces = selection.grep(Sketchup::Face).select(&:valid?)
        groups = selection.grep(Sketchup::Group)
        components = selection.grep(Sketchup::ComponentInstance)
        
        puts "\n=== ANÁLISE DA SELEÇÃO ATUAL ==="
        puts "Total de entidades: #{selection.length}"
        puts "Faces válidas: #{faces.length}"
        puts "Grupos: #{groups.length}"
        puts "Componentes: #{components.length}"
        puts "Outros: #{selection.length - faces.length - groups.length - components.length}"
        
        workflow_type = determine_workflow_type(faces, groups, components)
        puts "🔸 Workflow: #{workflow_type.upcase}"
        puts "================================\n"
        
        return {
          total: selection.length,
          faces: faces.length,
          groups: groups.length,
          components: components.length,
          workflow_type: workflow_type
        }
      end
      
      def determine_workflow_type(faces, groups, components)
        if faces.empty? && groups.empty? && components.empty?
          return :drawing
        elsif faces.any? && groups.empty? && components.empty?
          return :faces
        elsif groups.any? && faces.empty? && components.empty?
          return :groups
        elsif components.any? && faces.empty? && groups.empty?
          return :components
        else
          return :mixed
        end
      end
      
      # Função para verificar status do sistema
      def system_status
        puts "\n=== STATUS DO SISTEMA WORKFLOW ==="
        puts "SheetDetector: #{defined?(Rjv::MockupTools::SheetDetector) ? '✅ Disponível' : '❌ Não disponível'}"
        puts "MaterialSystem: #{defined?(Rjv::MockupTools::MaterialSystem) ? '✅ Disponível' : '❌ Não disponível'}"
        puts "FaceToBoard: #{defined?(Rjv::MockupTools::FaceToBoard) ? '✅ Disponível' : '❌ Não disponível'}"
        puts "GroupToComponent: #{defined?(Rjv::MockupTools::GroupToComponent) ? '✅ Disponível' : '❌ Não disponível'}"
        puts "==================================\n"
      end
    end
  end
end

# ===================================================================
# COMANDOS PARA CONSOLE DO SKETCHUP
# ===================================================================
#
# === SETUP INICIAL ===
#
# Verificar status do sistema:
# Rjv::MockupTools::IntelligentWorkflow.system_status
#
# === WORKFLOWS ===
#
# Workflow padrão (rigoroso):
# Rjv::MockupTools::IntelligentWorkflow.run
#
# Workflow rigoroso:
# Rjv::MockupTools::IntelligentWorkflow.run_strict
#
# Workflow permissivo:
# Rjv::MockupTools::IntelligentWorkflow.run_permissive
#
# Workflow legacy (sem validação):
# Rjv::MockupTools::IntelligentWorkflow.run_legacy
#
# Com material específico:
# Rjv::MockupTools::IntelligentWorkflow.run_with_material("MDF_18mm")
#
# === ANÁLISES ===
#
# Analisar seleção com validação de chapas:
# Rjv::MockupTools::IntelligentWorkflow.analyze_current_selection_with_validation
#
# Validação apenas (sem aplicar material):
# Rjv::MockupTools::IntelligentWorkflow.validate_selection_as_sheets
#
# Analisar seleção atual:
# Rjv::MockupTools::IntelligentWorkflow.analyze_current_selection
#
# ===================================================================