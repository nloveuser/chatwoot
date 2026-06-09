require 'ffi'
require 'json'

# Minimal TDLib JSON client using the new multi-client API (TDLib >= 1.7.0).
# Each process runs a single receiver loop that dispatches updates to all
# TdlibClient instances identified by their integer client_id.
#
# Requires: libtdjson.so present at TDLIB_LIB_PATH (default /usr/local/lib/libtdjson.so).
module TdlibJson
  extend FFI::Library

  LIB_PATH = ENV.fetch('TDLIB_LIB_PATH', '/usr/local/lib/libtdjson.so')

  begin
    ffi_lib LIB_PATH
    # New API (TDLib >= 1.7)
    attach_function :td_create_client_id, [], :int
    attach_function :td_send,    [:int, :string], :void
    attach_function :td_receive, [:double], :string
    attach_function :td_execute, [:string], :string
    AVAILABLE = true
  rescue LoadError => e
    warn "TDLib not available (#{LIB_PATH}): #{e.message}"
    AVAILABLE = false
  end
end

class TdlibClient
  RECEIVE_TIMEOUT = 1.0

  @registry      = {}
  @registry_lock = Mutex.new
  @req_counter   = 0
  @req_lock      = Mutex.new

  class << self
    def register(client_id, instance)
      @registry_lock.synchronize { @registry[client_id] = instance }
    end

    def unregister(client_id)
      @registry_lock.synchronize { @registry.delete(client_id) }
    end

    def dispatch(update)
      cid = update['@client_id']
      inst = @registry_lock.synchronize { @registry[cid] }
      inst&.handle_update(update)
    end

    def next_req_id
      @req_lock.synchronize { @req_counter += 1 }
    end
  end

  def initialize
    raise 'TDLib library not loaded' unless TdlibJson::AVAILABLE

    @id        = TdlibJson.td_create_client_id
    @callbacks = Hash.new { |h, k| h[k] = [] }
    @cb_lock   = Mutex.new
    @alive     = true
    self.class.register(@id, self)
  end

  # Register a callback for a given TDLib update type string.
  def on(type, &block)
    @cb_lock.synchronize { @callbacks[type] << block }
  end

  # Async request to this client.
  def request(payload)
    payload['@client_id'] = @id
    payload['@extra']     ||= self.class.next_req_id.to_s
    TdlibJson.td_send(@id, payload.to_json)
  end

  # Synchronous execute (no client context, for td_execute-able requests).
  def self.execute(payload)
    return nil unless TdlibJson::AVAILABLE

    result = TdlibJson.td_execute(payload.to_json)
    JSON.parse(result) if result
  rescue JSON::ParserError
    nil
  end

  def handle_update(update)
    type = update['@type']
    cbs  = @cb_lock.synchronize { @callbacks[type].dup }
    cbs.each { |cb| cb.call(update) }
  end

  def close
    @alive = false
    request({ '@type' => 'close' })
    self.class.unregister(@id)
  end

  def alive?
    @alive
  end

  def client_id
    @id
  end
end

# Single global receive loop — started once per process (e.g. from Sidekiq startup).
module TdlibReceiver
  class << self
    def start
      return unless TdlibJson::AVAILABLE
      return if @thread&.alive?

      @running = true
      @thread  = Thread.new { loop_until_stopped }
      @thread.abort_on_exception = false
      @thread
    end

    def stop
      @running = false
      @thread&.join(3)
    end

    private

    def loop_until_stopped
      while @running
        json = TdlibJson.td_receive(TdlibClient::RECEIVE_TIMEOUT)
        next unless json

        begin
          update = JSON.parse(json)
          TdlibClient.dispatch(update)
        rescue JSON::ParserError, StandardError => e
          Rails.logger.error("TdlibReceiver: #{e.class} #{e.message}") if defined?(Rails)
        end
      end
    end
  end
end
