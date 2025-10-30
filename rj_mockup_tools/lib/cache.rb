# encoding: UTF-8
# cache.rb
# Sistema de cache simples com TTL (Time To Live)

module Rjv
  module MockupTools
    module Cache
      extend self

      # Armazena os dados do cache
      @cache = {}

      # Estrutura de cache:
      # {
      #   key: {
      #     value: valor_armazenado,
      #     timestamp: Time.now,
      #     ttl: tempo_de_vida_em_segundos
      #   }
      # }

      # Obtém um valor do cache ou computa se necessário
      # @param key [String, Symbol] Chave do cache
      # @param ttl [Numeric] Tempo de vida em segundos (padrão: 2)
      # @yield Bloco para computar o valor se não estiver no cache
      # @return [Object] Valor em cache ou computado
      def fetch(key, ttl: 2)
        # Verifica se existe no cache e ainda é válido
        if cached?(key)
          @cache[key][:value]
        else
          # Computa novo valor
          value = yield if block_given?

          # Armazena no cache
          set(key, value, ttl: ttl)

          value
        end
      end

      # Define um valor no cache
      # @param key [String, Symbol] Chave
      # @param value [Object] Valor a armazenar
      # @param ttl [Numeric] Tempo de vida em segundos (padrão: 2)
      def set(key, value, ttl: 2)
        @cache[key] = {
          value: value,
          timestamp: Time.now,
          ttl: ttl
        }
        value
      end

      # Obtém um valor do cache (sem computar)
      # @param key [String, Symbol] Chave
      # @return [Object, nil] Valor ou nil se não existir/expirado
      def get(key)
        cached?(key) ? @cache[key][:value] : nil
      end

      # Verifica se uma chave está no cache e ainda é válida
      # @param key [String, Symbol] Chave
      # @return [Boolean]
      def cached?(key)
        return false unless @cache.key?(key)

        entry = @cache[key]
        now = Time.now

        # Verifica se não expirou
        if (now - entry[:timestamp]) <= entry[:ttl]
          true
        else
          # Remove entrada expirada
          @cache.delete(key)
          false
        end
      end

      # Invalida (remove) uma entrada do cache
      # @param key [String, Symbol] Chave
      def invalidate(key)
        @cache.delete(key)
      end

      # Limpa todo o cache
      def clear
        @cache.clear
      end

      # Limpa entradas expiradas
      # @return [Integer] Número de entradas removidas
      def cleanup
        now = Time.now
        expired_keys = []

        @cache.each do |key, entry|
          if (now - entry[:timestamp]) > entry[:ttl]
            expired_keys << key
          end
        end

        expired_keys.each { |key| @cache.delete(key) }
        expired_keys.size
      end

      # Retorna estatísticas do cache
      # @return [Hash] Estatísticas
      def stats
        now = Time.now
        valid_count = 0
        expired_count = 0

        @cache.each do |_, entry|
          if (now - entry[:timestamp]) <= entry[:ttl]
            valid_count += 1
          else
            expired_count += 1
          end
        end

        {
          total_entries: @cache.size,
          valid_entries: valid_count,
          expired_entries: expired_count,
          keys: @cache.keys
        }
      end

      # Executa um bloco e armazena em cache com memoização
      # Útil para operações caras que devem ser cacheadas
      # @param key [String, Symbol] Chave única
      # @param ttl [Numeric] Tempo de vida
      # @yield Bloco para computar o valor
      # @return [Object] Valor computado ou em cache
      def memoize(key, ttl: 5, &block)
        fetch(key, ttl: ttl, &block)
      end

      # Cache com invalidação baseada em condição
      # @param key [String, Symbol] Chave
      # @param ttl [Numeric] TTL padrão
      # @param invalidate_if [Proc] Proc que retorna true para invalidar
      # @yield Bloco para computar valor
      # @return [Object] Valor
      def conditional_fetch(key, ttl: 2, invalidate_if: nil)
        # Invalida se condição for verdadeira
        if invalidate_if && invalidate_if.call
          invalidate(key)
        end

        fetch(key, ttl: ttl) { yield if block_given? }
      end
    end

    # Cache especializado para contadores do plugin
    module CountersCache
      extend self

      DEFAULT_TTL = 1.5 # segundos

      # Contadores disponíveis
      COUNTERS = {
        makette_pieces: :count_makette_pro_pieces,
        pending_updates: :count_pending_updates,
        pending_engravings: :count_pending_engravings,
        mirrored_pieces: :count_mirrored_pieces,
        scaled_pieces: :count_scaled_pieces
      }.freeze

      # Obtém contador com cache
      # @param counter_name [Symbol] Nome do contador
      # @param force_refresh [Boolean] Força recálculo
      # @return [Integer] Valor do contador
      def get(counter_name, force_refresh: false)
        unless COUNTERS.key?(counter_name)
          raise ArgumentError, "Contador desconhecido: #{counter_name}"
        end

        key = "counter_#{counter_name}".to_sym

        # Invalida cache se force_refresh
        Cache.invalidate(key) if force_refresh

        # Busca com cache
        Cache.fetch(key, ttl: DEFAULT_TTL) do
          # Chama método de contagem correspondente
          count_method = COUNTERS[counter_name]
          send(count_method)
        end
      end

      # Invalida todos os contadores
      def invalidate_all
        COUNTERS.keys.each do |counter_name|
          Cache.invalidate("counter_#{counter_name}".to_sym)
        end
      end

      private

      # Implementações dos contadores
      # (Estas funções devem chamar as implementações reais do plugin)

      def count_makette_pro_pieces
        # Deve chamar: Rjv::MockupTools.count_makette_pro_pieces
        # Por enquanto retorna 0 como placeholder
        0
      end

      def count_pending_updates
        # Deve chamar: UpdateStamps.check_for_updates se módulo carregado
        0
      end

      def count_pending_engravings
        # Deve chamar: LaserEngraving.check_for_pending_engravings se módulo carregado
        0
      end

      def count_mirrored_pieces
        # Deve chamar: MirrorHandler.find_mirrored_makette_pro
        0
      end

      def count_scaled_pieces
        # Deve chamar: ScaleHandler.find_scaled_makette_pro
        0
      end
    end
  end
end
