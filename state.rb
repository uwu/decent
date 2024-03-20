# noinspection RubyClassVariableUsageInspection We want the undefined behavior, I promise.
module DecentState
  # An Unloadable is an object with a cleanup method used for disposing of hanging computations.
  class Unloadable
    def initialize(cleanup)
      @cleanup = cleanup
    end

    def cleanup
      @cleanup.call
    end
  end

  extend self

  @@effect_dependencies = nil
  @@current_computations = nil

  def effect_dependencies
    @@effect_dependencies
  end

  def current_computations
    @@current_computations
  end

  def scope(&computation_scope)
    previous_computations = @@current_computations
    computations = []
    @@current_computations = computations

    computation_scope.call

    previous_computations&.concat(computations)

    @@current_computations = previous_computations

    Unloadable.new -> do
      computations.each { |c| c.cleanup }
    end
  end

  def effect(dependencies = nil, &effect_callback)
    cleanups = []

    fire_effect = ->(dependencies = nil) {
      previous_dependencies = @@effect_dependencies

      @@effect_dependencies = dependencies.nil? ? [] : dependencies
      effect_callback.call if dependencies.nil?

      cleanups.each { |c| c.cleanup }
      cleanups = []

      @@effect_dependencies&.each { |dependency|
        # noinspection RubyResolve This is actually fine.
        cleanups.push(dependency.watch_reassignment { fire_effect.call })
      }

      @@effect_dependencies = previous_dependencies
    }

    fire_effect.call(dependencies)

    cleanup = Unloadable.new -> do
      cleanups.each { |c| c.cleanup }
    end

    @@current_computations&.push(cleanup)

    cleanup
  end

  class State
    def initialize(initial_state = nil)
      @visit_watchers = []
      @reassignment_watchers = []

      @state = initial_state
    end

    def value
      @visit_watchers.each { |watcher| watcher.call }

      deps = DecentState.effect_dependencies
      deps.push(self) unless deps.nil?

      @state
    end

    def value=(new)
      @state = new

      @reassignment_watchers.each { |watcher| watcher.call(new) }
    end

    def watch_visit(&callback)
      @visit_watchers.push callback

      Unloadable.new -> do
        @visit_watchers.delete callback
      end
    end

    def watch_reassignment(&callback)
      @reassignment_watchers.push callback

      Unloadable.new -> do
        @reassignment_watchers.delete callback
      end
    end

    def watch(&callback)
      unwatchers = [watch_visit(&callback), watch_reassignment(&callback)]

      Unloadable.new -> do
        unwatchers.each { |unwatch| unwatch.cleanup }
      end
    end
  end

  class DerivedState < State
    def initialize(&calculation)
      super nil

      @cleanup = DecentState.effect do
        self.value = calculation.call
      end
    end

    def cleanup
      @cleanup.cleanup
    end
  end

  # Creates a new reactive state object.
  def state(initial = nil)
    State.new initial
  end

  def derived(&calculation)
    DerivedState.new(&calculation)
  end

  def is_state?(obj)
    obj.is_a?(State) || obj.is_a?(DerivedState)
  end

  def unwrap_state(obj)
    if is_state? obj
      obj.value
    else
      obj
    end
  end

  def unwrap_hash(hash)
    hash.map {|k, v| [k, unwrap_state(v)]}.to_h
  end
end