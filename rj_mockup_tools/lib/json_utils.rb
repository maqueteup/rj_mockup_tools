# encoding: UTF-8
# json_utils.rb
# Utilitários para manipulação de JSON

require 'json'

module Rjv
  module MockupTools
    module JsonUtils
      extend self

      # Arredonda floats recursivamente em estruturas de dados
      # @param obj [Object] Objeto a processar
      # @param precision [Integer] Número de casas decimais (padrão: 3)
      # @return [Object] Objeto com floats arredondados
      def round_floats(obj, precision = 3)
        case obj
        when Hash
          obj.transform_values { |v| round_floats(v, precision) }
        when Array
          obj.map { |v| round_floats(v, precision) }
        when Float
          # Arredonda para N casas decimais
          obj.round(precision)
        else
          obj
        end
      end

      # Carrega JSON com tratamento de erros
      # @param file_path [String] Caminho do arquivo
      # @param symbolize [Boolean] Simbolizar chaves (padrão: true)
      # @return [Hash, Array, nil] Dados parseados ou nil em caso de erro
      def load_json(file_path, symbolize: true)
        return nil unless File.exist?(file_path)

        begin
          content = File.read(file_path)
          JSON.parse(content, symbolize_names: symbolize)
        rescue JSON::ParserError => e
          puts "ERRO: Falha ao parsear JSON em '#{File.basename(file_path)}': #{e.message}"
          nil
        rescue => e
          puts "ERRO: Falha ao ler arquivo '#{File.basename(file_path)}': #{e.message}"
          nil
        end
      end

      # Salva JSON com formatação e arredondamento
      # @param file_path [String] Caminho do arquivo
      # @param data [Object] Dados a salvar
      # @param precision [Integer] Casas decimais para floats (padrão: 3)
      # @return [Boolean] true se salvou com sucesso
      def save_json(file_path, data, precision: 3)
        begin
          # Arredonda floats antes de salvar
          rounded_data = round_floats(data, precision)

          # Cria diretório se não existir
          dir = File.dirname(file_path)
          Dir.mkdir(dir) unless Dir.exist?(dir)

          # Salva com formatação bonita
          File.write(file_path, JSON.pretty_generate(rounded_data))
          true
        rescue => e
          puts "ERRO: Falha ao salvar JSON em '#{File.basename(file_path)}': #{e.message}"
          false
        end
      end

      # Valida estrutura básica de um JSON de materiais
      # @param data [Hash] Dados a validar
      # @return [Hash] { valid: Boolean, errors: Array<String> }
      def validate_materials_json(data)
        errors = []

        unless data.is_a?(Hash)
          return { valid: false, errors: ["Root deve ser um Hash"] }
        end

        # Verifica chaves obrigatórias
        [:types, :materials].each do |key|
          unless data.key?(key) || data.key?(key.to_s)
            errors << "Chave obrigatória ausente: '#{key}'"
          end
        end

        # Valida tipos
        types = data[:types] || data['types']
        if types && !types.is_a?(Array)
          errors << "'types' deve ser um Array"
        elsif types
          types.each_with_index do |type, i|
            unless type.is_a?(Hash) && (type[:name] || type['name'])
              errors << "Type[#{i}] inválido: deve ter campo 'name'"
            end
          end
        end

        # Valida materiais
        materials = data[:materials] || data['materials']
        if materials && !materials.is_a?(Array)
          errors << "'materials' deve ser um Array"
        elsif materials
          materials.each_with_index do |mat, i|
            required_fields = [:name, :thickness, :layer]
            required_fields.each do |field|
              unless mat[field] || mat[field.to_s]
                errors << "Material[#{i}] sem campo obrigatório '#{field}'"
              end
            end

            # Valida thickness
            thickness = mat[:thickness] || mat['thickness']
            if thickness && (!thickness.is_a?(Numeric) || thickness <= 0)
              errors << "Material[#{i}] com thickness inválido: #{thickness}"
            end
          end
        end

        { valid: errors.empty?, errors: errors }
      end

      # Corrige arquivo JSON com precisão de floats
      # @param file_path [String] Caminho do arquivo
      # @param precision [Integer] Casas decimais (padrão: 3)
      # @return [Boolean] true se corrigiu com sucesso
      def fix_json_precision(file_path, precision: 3)
        puts "Corrigindo precisão em: #{File.basename(file_path)}"

        data = load_json(file_path)
        return false unless data

        # Faz backup
        backup_path = "#{file_path}.backup"
        FileUtils.cp(file_path, backup_path) rescue nil

        # Salva com precisão corrigida
        if save_json(file_path, data, precision: precision)
          puts "✅ Arquivo corrigido: #{File.basename(file_path)}"
          true
        else
          puts "❌ Falha ao corrigir: #{File.basename(file_path)}"
          false
        end
      end
    end
  end
end
