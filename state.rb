# noinspection RubyClassVariableUsageInspection We want the undefined behavior, I promise.
module DecentState
  extend self

  @@effect_dependencies = []
  @@current_computations = []

  def effect_dependencies
    @@effect_dependencies
  end

  def current_computations
    @@current_computations
  end
  
  # An Unloadable is an object with a cleanup method used for disposing of hanging computations.
  class Unloadable
    def initialize(scope, &cleanup)
      @cleanup = cleanup
      @scope = scope
    end

    def cleanup
      @scope&.delete self
      @cleanup&.call
      @scope = nil
      @cleanup = nil
    end
  end

  def scope(&computation_scope)
    previous_computations = @@current_computations
    computations = []
    @@current_computations = computations

    computation_scope.call

    @@current_computations = previous_computations

    cleanup = Unloadable.new previous_computations do
      computations.each { |c| c.cleanup }
      computations = []
    end

    previous_computations.push(cleanup)

    cleanup
  end

  def effect(dependencies = nil, &effect_callback)
    cleanups = []

    if dependencies.is_a? Array
      dependencies.each do |dependency|
        cleanups.push(dependency.watch_reassignment {
          previous_dependencies = @@effect_dependencies
          @@effect_dependencies = []
          effect_callback.call
          @@effect_dependencies = previous_dependencies
        })
      end
    else
      recalculate_dependencies = -> {
        previous_dependencies = @@effect_dependencies
        @@effect_dependencies = []

        # For some reason, RubyMine cannot figure out that this *does* have access to the outer scope.
        cleanups.each(&:cleanup)
        cleanups = []
        effect_callback.call

        @@effect_dependencies.each do |dependency|
          cleanups.push(dependency.watch_reassignment {
            recalculate_dependencies.call
          })
        end

        @@effect_dependencies = previous_dependencies
      }

      recalculate_dependencies.call
    end

    cleanup = Unloadable.new @@current_computations do
      cleanups.each { |c| c.cleanup }
      cleanups = []
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

    def untracked
      @state
    end

    def untracked=(new)
      @state = (new)
    end

    def value
      @visit_watchers.each { |watcher| watcher.call }

      deps = DecentState.effect_dependencies
      deps.push(self) unless deps.include? self

      @state
    end

    def value=(new)
      @state = new

      @reassignment_watchers.each { |watcher| watcher.call(new) }
    end

    def watch_visit(&callback)
      @visit_watchers.push callback

      Unloadable.new [] do
        @visit_watchers.delete callback
      end
    end

    def watch_reassignment(&callback)
      @reassignment_watchers.push callback

      Unloadable.new [] do
        @reassignment_watchers.delete callback
      end
    end

    def watch(&callback)
      unwatchers = [watch_visit(&callback), watch_reassignment(&callback)]

      Unloadable.new [] do
        unwatchers.each { |unwatch| unwatch.cleanup }
        unwatchers = []
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
    hash.map { |k, v| [k, unwrap_state(v)] }.to_h
  end

  def reactive(hash = {})
    # TODO: Overhaul this entire thing to use a real hash.
    fake_hash = Object.new

    hash.each_pair do |key, value|
      ref = state value

      fake_hash.define_singleton_method(key) { ref.value }
      fake_hash.define_singleton_method((key.to_s + "=").to_sym) { |new| ref.value = new }
    end

    fake_hash
  end
end