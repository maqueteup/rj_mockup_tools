# lib/menus.rb (OTIMIZADO - Lazy Loading)
# encoding: UTF-8

module Rjv
  module MockupTools
    module Menus
      def self.create_ui
        extensions_menu = UI.menu("Extensions")
        mockup_submenu = extensions_menu.add_submenu(PLUGIN_NAME)

        # ===== MODELAGEM =====
        model_submenu = mockup_submenu.add_submenu("Modelagem")
        
        model_submenu.add_item("Criar Painel Dividido...") {
          Rjv::MockupTools.ensure_loaded('PanelDividerTool')
          Rjv::MockupTools.activate_panel_divider_tool
        }

        model_submenu.add_item("Resetar Eixos (UCS)") {
          # ResetUCS já está carregado no início
          Rjv::MockupTools::ResetUCS.run
        }

        model_submenu.add_item("Resetar Eixos (Escolher Canto)") {
          # ResetUCS já está carregado no início
          Rjv::MockupTools::ResetUCS.run_interactive
        }

        model_submenu.add_item("Inverter Eixo Z (UCS)") {
          Rjv::MockupTools.ensure_loaded('FlipUCS')
          Rjv::MockupTools::FlipUCS.run
        }

        model_submenu.add_item("Renomear Entidades...") {
          Rjv::MockupTools.ensure_loaded('RenameEntities')
          Rjv::MockupTools::RenameEntities.run
        }
       
        stretch_submenu = model_submenu.add_submenu("🔧 Stretch Tools")
        
        stretch_submenu.add_item("Stretch (Bounding Box)") { 
          Rjv::MockupTools.ensure_loaded('StretchTool')
          Sketchup.active_model.select_tool(Rjv::MockupTools::StretchTool.new) 
        }
        
        stretch_submenu.add_item("Stretch (Face Personalizada)") { 
          Rjv::MockupTools.ensure_loaded('StretchFaceTool')
          Sketchup.active_model.select_tool(Rjv::MockupTools::StretchFaceTool.new) 
        }
        
        rot_submenu = model_submenu.add_submenu("Rotacionar Eixo Local +90°")
        
        rot_submenu.add_item("Eixo X") { 
          Rjv::MockupTools.ensure_loaded('RotateLocalAxisSelectionCenter')
          Rjv::MockupTools::RotateLocalAxisSelectionCenter.rotate_local_x 
        }
        
        rot_submenu.add_item("Eixo Y") { 
          Rjv::MockupTools.ensure_loaded('RotateLocalAxisSelectionCenter')
          Rjv::MockupTools::RotateLocalAxisSelectionCenter.rotate_local_y 
        }
        
        rot_submenu.add_item("Eixo Z") { 
          Rjv::MockupTools.ensure_loaded('RotateLocalAxisSelectionCenter')
          Rjv::MockupTools::RotateLocalAxisSelectionCenter.rotate_local_z 
        }
        
        mockup_submenu.add_separator

        # ===== CARIMBOS =====
        stamps_submenu = mockup_submenu.add_submenu("Carimbos (Texto 3D)")
        
        stamps_submenu.add_item("Aplicar Carimbo") { 
          Rjv::MockupTools.ensure_loaded('StampName')
          Rjv::MockupTools::StampName.run 
        }
        
        stamps_submenu.add_item("Configurar Carimbo...") { 
          Rjv::MockupTools.ensure_loaded('StampName')
          Rjv::MockupTools::StampName.configure_stamp_settings 
        }
        
        stamps_submenu.add_item("Selecionar Todos os Carimbos") { 
          Rjv::MockupTools.ensure_loaded('SelectStamps')
          Rjv::MockupTools::SelectStamps.select_all_stamps 
        }
        
        stamps_submenu.add_item("Atualizar Carimbos") { 
          Rjv::MockupTools.ensure_loaded('UpdateStamps')
          Rjv::MockupTools::UpdateStamps.run 
        }
        
        mockup_submenu.add_separator
        
        # ===== PRODUÇÃO =====
        production_submenu = mockup_submenu.add_submenu("Produção")

        production_submenu.add_item("Aplicar Impressão 3D") {
          Rjv::MockupTools.ensure_loaded('Apply3DPrint')
          Rjv::MockupTools::Apply3DPrint.run
        }

        production_submenu.add_item("Planificar Peças") {
          Rjv::MockupTools.ensure_loaded('Planifier')
          Rjv::MockupTools::Planifier.run 
        }
        
        production_submenu.add_item("Gerar Relatório de Planificação") { 
          Rjv::MockupTools.ensure_loaded('ReportGenerator')
          Rjv::MockupTools::ReportGenerator.generate_layout_report 
        }

        production_submenu.add_item("Configurar Informações do Projeto") {
          Rjv::MockupTools.ensure_loaded('ReportGenerator')
          Rjv::MockupTools::ReportGenerator.configure_project
        }

        production_submenu.add_item("Gerar Gravação a Laser (Seleção)") { 
          Rjv::MockupTools.ensure_loaded('LaserEngraving')
          Rjv::MockupTools::LaserEngraving.run_on_selection 
        }
        
        production_submenu.add_item("Gerar Todas as Gravações Pendentes") { 
          Rjv::MockupTools.ensure_loaded('LaserEngraving')
          Rjv::MockupTools::LaserEngraving.run_on_all_pending 
        }
        
        mockup_submenu.add_separator

        # ===== ANÁLISE =====
        analysis_submenu = mockup_submenu.add_submenu("Análise")
        
        analysis_submenu.add_item("🔍 Model Inspector") { 
          Rjv::MockupTools.ensure_loaded('ModelInspector')
          Rjv::MockupTools::ModelInspector.open_dialog 
        }
        
        analysis_submenu.add_item("Analisador de Colisões") { 
          Rjv::MockupTools.ensure_loaded('CollisionAnalyzer')
          Rjv::MockupTools::CollisionAnalyzer.open_dialog 
        }
        
        # ✅ Menu com validação (carrega ColorByLayerToggle sob demanda)
        cmd_color_by_layer = UI::Command.new("Cor por Camada") { 
          Rjv::MockupTools.ensure_loaded('ColorByLayerToggle')
          Rjv::MockupTools::ColorByLayerToggle.toggle 
        }
        
        cmd_color_by_layer.set_validation_proc {
          # Carrega módulo apenas se necessário para verificação
          if Rjv::MockupTools.ensure_loaded('ColorByLayerToggle')
            Rjv::MockupTools::ColorByLayerToggle.is_active? ? MF_CHECKED : MF_UNCHECKED
          else
            MF_UNCHECKED
          end
        }
        
        analysis_submenu.add_item(cmd_color_by_layer)

        mockup_submenu.add_separator

        # ===== GERENCIAMENTO =====
        management_submenu = mockup_submenu.add_submenu("Gerenciamento")
        
        management_submenu.add_item("Gerenciador de Materiais") { 
          # MaterialSystem já está carregado no início
          Rjv::MockupTools::MaterialSystem.open_property_editor 
        }
        
        management_submenu.add_item("Gerenciador de Cores") { 
          Rjv::MockupTools.ensure_loaded('MaterialColorManager')
          Rjv::MockupTools::MaterialColorManager.open_dialog 
        }

        # ===== MENU DE CONTEXTO =====
        UI.add_context_menu_handler do |context_menu|
          selection = Sketchup.active_model.selection
          
          if !selection.empty? && Sketchup.active_model.active_path != nil
            # Só carrega se necessário
            if Rjv::MockupTools.ensure_loaded('GroupInternalEdges')
              if defined?(Rjv::MockupTools::GroupInternalEdges)
                main_submenu = context_menu.add_submenu("RJV Mockup Tools")
                main_submenu.add_item("Agrupar Arestas Internas da Seleção") { 
                  Rjv::MockupTools::GroupInternalEdges.run_on_active_selection 
                }
              end
            end
          end
        end

        puts "✅ #{Rjv::MockupTools::PLUGIN_NAME} v#{Rjv::MockupTools::VERSION}: Menus criados (LAZY LOADING)"
      end
    end
  end
end