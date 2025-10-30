# encoding: UTF-8
# logger.rb
# Sistema de logging estruturado para o plugin

module Rjv
  module MockupTools
    module Logger
      extend self

      # Níveis de log disponíveis
      LEVELS = {
        DEBUG: 0,
        INFO: 1,
        WARN: 2,
        ERROR: 3,
        FATAL: 4
      }.freeze

      # Cores para terminal (opcional)
      COLORS = {
        DEBUG: "\e[36m",   # Cyan
        INFO: "\e[32m",    # Green
        WARN: "\e[33m",    # Yellow
        ERROR: "\e[31m",   # Red
        FATAL: "\e[35m",   # Magenta
        RESET: "\e[0m"
      }.freeze

      # Nível mínimo de log (pode ser configurado)
      @level = LEVELS[:INFO]
      @use_colors = true
      @log_to_file = false
      @log_file_path = nil

      # Configura o nível de log
      # @param level [Symbol] :DEBUG, :INFO, :WARN, :ERROR, :FATAL
      def set_level(level)
        if LEVELS.key?(level)
          @level = LEVELS[level]
          info("Nível de log alterado para: #{level}")
        else
          warn("Nível de log inválido: #{level}")
        end
      end

      # Habilita/desabilita cores no terminal
      # @param enabled [Boolean]
      def set_colors(enabled)
        @use_colors = enabled
      end

      # Configura logging para arquivo
      # @param file_path [String, nil] Caminho do arquivo ou nil para desabilitar
      def set_log_file(file_path)
        @log_file_path = file_path
        @log_to_file = !file_path.nil?

        if @log_to_file
          begin
            # Cria diretório se necessário
            dir = File.dirname(file_path)
            Dir.mkdir(dir) unless Dir.exist?(dir)

            # Testa escrita
            File.open(file_path, 'a') { |f| f.puts("=== Log iniciado em #{Time.now} ===") }
            info("Logging para arquivo habilitado: #{file_path}")
          rescue => e
            @log_to_file = false
            @log_file_path = nil
            error("Falha ao configurar arquivo de log: #{e.message}")
          end
        end
      end

      # Log de DEBUG
      def debug(message, context = nil)
        log(:DEBUG, message, context) if @level <= LEVELS[:DEBUG]
      end

      # Log de INFO
      def info(message, context = nil)
        log(:INFO, message, context) if @level <= LEVELS[:INFO]
      end

      # Log de WARN
      def warn(message, context = nil)
        log(:WARN, message, context) if @level <= LEVELS[:WARN]
      end

      # Log de ERROR
      def error(message, context = nil)
        log(:ERROR, message, context) if @level <= LEVELS[:ERROR]
      end

      # Log de FATAL
      def fatal(message, context = nil)
        log(:FATAL, message, context) if @level <= LEVELS[:FATAL]
      end

      # Log com medição de tempo
      # @param message [String] Mensagem
      # @param level [Symbol] Nível de log
      # @yield Bloco a executar
      # @return [Object] Resultado do bloco
      def timed(message, level: :INFO)
        start_time = Time.now
        send(level.downcase, "Iniciando: #{message}")

        result = yield if block_given?

        elapsed = Time.now - start_time
        send(level.downcase, "Concluído: #{message} (#{format_duration(elapsed)})")

        result
      rescue => e
        elapsed = Time.now - start_time
        error("Falha em: #{message} (#{format_duration(elapsed)}): #{e.message}")
        raise e
      end

      private

      # Formata uma mensagem de log
      def format_message(level, message, context = nil)
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        level_str = level.to_s.ljust(5)

        if context
          "[#{timestamp}] [#{level_str}] [#{context}] #{message}"
        else
          "[#{timestamp}] [#{level_str}] #{message}"
        end
      end

      # Formata duração em formato legível
      def format_duration(seconds)
        if seconds < 0.001
          "#{(seconds * 1_000_000).round(0)}µs"
        elsif seconds < 1
          "#{(seconds * 1000).round(2)}ms"
        elsif seconds < 60
          "#{seconds.round(3)}s"
        else
          minutes = (seconds / 60).floor
          secs = (seconds % 60).round(1)
          "#{minutes}m #{secs}s"
        end
      end

      # Escreve log
      def log(level, message, context = nil)
        formatted = format_message(level, message, context)

        # Log para console (Ruby console no SketchUp)
        if @use_colors && COLORS.key?(level)
          puts "#{COLORS[level]}#{formatted}#{COLORS[:RESET]}"
        else
          puts formatted
        end

        # Log para arquivo (se habilitado)
        if @log_to_file && @log_file_path
          begin
            File.open(@log_file_path, 'a') { |f| f.puts(formatted) }
          rescue => e
            puts "[ERROR] Falha ao escrever no arquivo de log: #{e.message}"
          end
        end
      rescue => e
        # Fallback para puts simples em caso de erro no logging
        puts "[#{level}] #{message} (ERRO NO LOGGER: #{e.message})"
      end
    end
  end
end
