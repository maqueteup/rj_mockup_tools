def self.apply_style(model, style_data)
  return unless style_data.is_a?(Hash)
  
  style_name = "#{style_data[:name]} (Importado)"
  
  # Primeiro, tenta encontrar o estilo existente
  style = model.styles[style_name]
  
  # Se o estilo não existir, cria corretamente
  unless style
    begin
      # Usa o estilo ativo atual como base e duplica
      current_style = model.styles.active_style
      style = model.styles.add_style(current_style.name + "_temp", false)
      
      # Renomeia o estilo para o nome desejado
      # Nota: SketchUp pode não permitir renomeação direta, então trabalhamos com o que temos
      style_name = style.name  # Usa o nome real que foi criado
    rescue => e
      puts "Erro ao criar estilo: #{e.message}"
      return
    end
  end
  
  # Verifica se temos um objeto de estilo válido
  unless style.is_a?(Sketchup::Style)
    puts "Erro: Falha ao criar ou recuperar objeto de estilo válido"
    return
  end
  
  # Define o estilo como ativo
  begin
    model.styles.selected_style = style
  rescue => e
    puts "Erro ao definir estilo selecionado: #{e.message}"
    return
  end
  
  # Apply the properties
  rop = model.rendering_options
  si = model.shadow_info
  properties = style_data[:properties] || {}

  properties.each_pair do |key, value|
    # Verifica se a propriedade pertence a RenderingOptions ou ShadowInfo
    if rop.keys.include?(key.to_s)
      # Reconstrói a cor se necessário
      value = Sketchup::Color.new(*value) if value.is_a?(Array) && value.length == 4
      begin
        rop[key.to_s] = value
      rescue => e
        puts "Error setting rendering option #{key}: #{e.message}"
      end
    elsif si.keys.include?(key.to_s)
      begin
        si[key.to_s] = value
      rescue => e
        puts "Error setting shadow info #{key}: #{e.message}"
      end
    end
  end

  # Update the style
  begin
    model.styles.update_selected_style
  rescue => e
    puts "Error updating selected style: #{e.message}"
  end
end