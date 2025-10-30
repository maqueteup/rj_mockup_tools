# encoding: UTF-8
# Mockup Tools RJV - Highlight Local Bottom (-Z) Face Tool (Draw Text Feedback)

require 'sketchup.rb'

module Rjv
  module MockupTools
    module HighlightLocalBottomFace

      # --- Constantes ---
      HIGHLIGHT_COLOR = Sketchup::Color.new(255, 0, 0, 100).freeze # Vermelho semi-transparente
      OVERLAY_ID = 'rj_mockup_tools_highlight_local_bottom'.freeze
      TOLERANCE = 1e-4
      Z_AXIS = Geom::Vector3d.new(0, 0, 1).freeze
      NEG_Z_AXIS_LOCAL = Geom::Vector3d.new(0, 0, -1).freeze
      # Constantes para o texto de feedback na tela
      FEEDBACK_TEXT = "CHECAGEM DE FACES ATIVA".freeze
      FEEDBACK_TEXT_COLOR = Sketchup::Color.new(80, 80, 80).freeze # Cinza escuro
      FEEDBACK_BG_COLOR = Sketchup::Color.new(255, 255, 150, 200).freeze # Amarelo pálido semi-transparente
      FEEDBACK_PADDING = 20 # Pixels de espaçamento interno do banner
      FEEDBACK_FONT_SIZE = 20 # Tamanho da fonte (aproximado em pontos)
      FEEDBACK_Y_POS = 750 # Distância do topo da viewport (pixels)

      # --- Classe do Overlay (com draw_text) ---
      class LocalBottomFaceOverlay < Sketchup::Overlay
        attr_accessor :active # Flag para controlar desenho e análise

        def initialize
          super(OVERLAY_ID, "Highlight Local Bottom Face") # ID e Nome do Overlay
          @points_to_draw = [] # Armazena vértices dos triângulos em coordenadas MUNDO
          @bounds = Geom::BoundingBox.new # Bounding box dos triângulos desenhados
          @active = false # O overlay começa desativado
        end

        # Método chamado pelo SketchUp para desenhar na tela
        def draw(view)
          # 1. Desenha destaque das faces -Z locais (se ativo e houver pontos)
          if @active && @points_to_draw.size >= 3
            view.drawing_color = HIGHLIGHT_COLOR
            view.line_stipple = ''
            view.line_width = 1
            # Desenha os triângulos preenchidos
            view.draw(GL_TRIANGLES, @points_to_draw)
          end

          # 2. Desenha o Banner de Texto "CHECAGEM DE FACES ATIVA" (se ativo)
          if @active
            begin
              # Calcula dimensões e posição do banner na tela (2D)
              vp_width = view.vpwidth
              vp_height = view.vpheight

              # Estimativa da largura do texto (pode variar com a fonte real usada)
              # Ajuste o fator 0.6 se o texto sair do banner
              text_width_approx = FEEDBACK_TEXT.length * (FEEDBACK_FONT_SIZE * 0.8)
              # Altura pode ser baseada no tamanho da fonte
              text_height_approx = FEEDBACK_FONT_SIZE * 1.4
              banner_width = text_width_approx + (FEEDBACK_PADDING * 2)
              banner_height = text_height_approx + (FEEDBACK_PADDING * 2)

              # Posição X/Y do canto INFERIOR ESQUERDO do banner na tela
              banner_x = (vp_width / 2.0) - (banner_width / 2.0)
              banner_y = vp_height - FEEDBACK_Y_POS - banner_height # Y cresce de baixo para cima

              # Garante que coords são inteiros para draw2d se necessário (geralmente não precisa)
              banner_x = banner_x.to_i
              banner_y = banner_y.to_i

              # Desenha o fundo retangular do banner
              view.drawing_color = FEEDBACK_BG_COLOR
              pts_bg = [
                [banner_x, banner_y, 0],
                [banner_x + banner_width, banner_y, 0],
                [banner_x + banner_width, banner_y + banner_height, 0],
                [banner_x, banner_y + banner_height, 0]
              ]
              view.draw2d(GL_QUADS, pts_bg)

              # Desenha o texto sobre o fundo
              view.drawing_color = FEEDBACK_TEXT_COLOR
              # Posição do texto (canto inferior esquerdo do texto dentro do banner)
              text_x = banner_x + FEEDBACK_PADDING
              text_y = banner_y + FEEDBACK_PADDING
              text_pt = Geom::Point3d.new(text_x, text_y, 0)
              # Opções para draw_text (verificar documentação para mais opções)
              text_options = {
                font: "Arial", # Tenta usar uma fonte comum
                size: FEEDBACK_FONT_SIZE,
                bold: true,
                color: FEEDBACK_TEXT_COLOR
              }
              view.draw_text(text_pt, FEEDBACK_TEXT, text_options)

            rescue => e
               puts "Erro ao desenhar banner de texto: #{e.message}"
               # Ignora erro de desenho silenciosamente
            end
          end # Fim if @active (para banner)
        end # Fim draw

        # Retorna a bounding box do conteúdo desenhado
        def getExtents
          # Só retorna bounds reais se ativo, senão vazio
          @active ? @bounds : Geom::BoundingBox.new
        end

        # Limpa os dados atuais do overlay
        def clear_data
           @points_to_draw.clear
           @bounds = Geom::BoundingBox.new
        end

        # Adiciona os pontos dos triângulos (coordenadas MUNDO)
        def add_world_triangles(world_points_array)
            return unless world_points_array.is_a?(Array) && world_points_array.size >= 3 && world_points_array.size % 3 == 0
            @points_to_draw.concat(world_points_array)
            # Adiciona pontos ao bounds com segurança
            world_points_array.each { |pt| @bounds.add(pt) if pt.is_a?(Geom::Point3d) }
        rescue => e
            puts "Erro ao adicionar pontos ao overlay bounds: #{e.message}"
        end
      end # Fim class LocalBottomFaceOverlay


      # --- Gerenciamento ---
      @overlay = nil # Guarda a instância do overlay

      # Ativa/Desativa/Atualiza o Overlay e o Banner
      def self.toggle_highlight
        model = Sketchup.active_model

        # Garante que temos apenas uma instância do nosso overlay registrada
        unless @overlay && model.overlays.map(&:overlay_id).include?(OVERLAY_ID)
            old_overlay = model.overlays.find { |o| o.overlay_id == OVERLAY_ID }
            model.overlays.remove(old_overlay) if old_overlay
            @overlay = LocalBottomFaceOverlay.new
            model.overlays.add(@overlay)
            puts "HighlightLocalBottom: Overlay Criado/Adicionado."
        end

        # Alterna o estado ativo
        @overlay.active = !@overlay.active

        if @overlay.active
            puts "HighlightLocalBottom: ATIVANDO..."
            Sketchup.status_text = "Destacando faces Z-Local Negativo. Clique de novo para desativar."
            @overlay.clear_data # Limpa antes de analisar

            # Analisa a seleção ATUAL para popular o overlay
            analyze_selection_for_local_negz(model.selection, @overlay)
            # O banner será desenhado automaticamente pelo método draw do overlay
        else
            puts "HighlightLocalBottom: DESATIVANDO..."
            Sketchup.status_text = ""
            @overlay.clear_data # Limpa os pontos (o banner sumirá pois @active é false)
        end
        # Força a view a redesenhar
        model.active_view.invalidate
      end # Fim toggle_highlight


      # --- Funções Auxiliares Privadas ---

      # Inicia análise da seleção
      private_class_method def self.analyze_selection_for_local_negz(selection, overlay)
         return unless selection && overlay && overlay.active
         puts "   - Analisando #{selection.length} itens selecionados..."
         selection.each do |entity|
            next unless entity&.valid?
            # Começa recursão com transformação identidade
            analyze_entity_recursively(entity, Geom::Transformation.new, overlay)
         end
         # Invalida a view após terminar a análise para mostrar resultados
         Sketchup.active_model.active_view.invalidate
         puts "   - Análise concluída."
      end # Fim analyze_selection_for_local_negz

      # Função recursiva para encontrar faces -Z local (Formatada)
      private_class_method def self.analyze_entity_recursively(entity, parent_world_transform, overlay)
            return unless entity&.valid? && overlay && overlay.active
            # Processa apenas tipos relevantes
            return unless entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

            # Calcula transformação mundo atual (APENAS se for container)
            current_world_transform = parent_world_transform
            if entity.respond_to?(:transformation)
                current_world_transform = parent_world_transform * entity.transformation
            end

            if entity.is_a?(Sketchup::Face)
                # Processa a Face
                begin
                    local_normal = entity.normal
                    # Pula se normal local inválida
                    unless local_normal.valid? && local_normal.length > TOLERANCE
                        return # Sai para esta face
                    end

                    # Verifica se aponta para -Z LOCAL
                    if local_normal.parallel?(NEG_Z_AXIS_LOCAL) && local_normal.z < -TOLERANCE
                        # Coleta triângulos em coordenadas MUNDO
                        mesh = entity.mesh(7) # Pega polígonos e pontos
                        triangles_world_points = []
                        mesh.polygons.each do |poly_indices|
                           next if poly_indices.nil? || poly_indices.empty?
                           points = poly_indices.map { |index| mesh.point_at(index.abs) }
                           # Triangula se necessário
                           if points.length >= 3
                                (1..(points.length - 2)).each do |i|
                                   tri = [points[0], points[i], points[i+1]]
                                   # Transforma pontos locais da face para MUNDO usando TF do PAI
                                   world_points = tri.map { |pt| pt.transform(parent_world_transform) }
                                   triangles_world_points.concat(world_points)
                                end
                           end
                        end # Fim loop polígonos
                        # Adiciona ao overlay
                        overlay.add_world_triangles(triangles_world_points) if triangles_world_points.any?
                    end
                rescue => e
                    puts "  - Erro ao analisar face #{entity.entityID}: #{e.message}"
                    # Continua para próxima entidade no loop pai
                end

            elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                # Processa o Container (Grupo ou Instância)
                begin
                  definition_entities = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
                  # Chama recursivamente para entidades internas, passando a TF MUNDO acumulada
                  definition_entities.each do |inner_entity|
                      analyze_entity_recursively(inner_entity, current_world_transform, overlay)
                  end
                rescue => e
                   puts "  - Erro ao processar container #{entity.entityID}: #{e.message}"
                   # Continua
                end
            end # Fim if/elsif tipo entidade
       end # Fim analyze_entity_recursively

       # --- Funções não mais necessárias aqui ---
       # get_or_create_layer

    end # module HighlightLocalBottomFace
  end # module MockupTools
end # module Rjv