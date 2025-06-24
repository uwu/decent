require "objspace"

# noinspection RubyClassVariableUsageInspection We want the undefined behavior, I promise.
module DecentState
  extend self

  @@fiber_current_effects = ObjectSpace::WeakMap.new
  @@fiber_current_scopes = ObjectSpace::WeakMap.new

  def current_effect
    @@fiber_current_effects[Fiber.current]
  end

  def current_effect=(new_value)
    @@fiber_current_effects[Fiber.current] = new_value
  end

  def current_scope
    @@fiber_current_scopes[Fiber.current]
  end

  def current_scope=(new_value)
    @@fiber_current_scopes[Fiber.current] = new_value
  end

  class State
    def initialize(initial_state = nil)
      @state = initial_state
      @reassignment_watchers = []
    end

    def untracked
      @state
    end

    def untracked=(new)
      @state = (new)
    end

    def value
      current_effect = DecentState.current_effect
      add_observer(current_effect) if current_effect

      @state
    end

    def value=(new)
      return if new == @state

      @state = new

      @reassignment_watchers.each do |effect|
        effect.notify
      end
    end

    def add_observer(effect)
      effect.dependencies.push self unless effect.dependencies.include? self
      @reassignment_watchers.push effect unless @reassignment_watchers.include? effect
    end

    def remove_observer(effect)
      effect.dependencies.delete self
      @reassignment_watchers.delete effect
    end
  end

  class Effect
    def initialize(dependencies = nil, &notify)
      @dependencies = []
      @notify = notify

      if dependencies.nil?
        capture_dependencies &notify
      else
        dependencies.each do |dependency|
          dependency.add_observer(self)
        end
      end

      DecentState.current_scope&.computations&.push self
    end

    def capture_dependencies
      previous_effect = DecentState.current_effect
      DecentState.current_effect = self
      yield
      DecentState.current_effect = previous_effect
    end

    def notify
      previous_effect = DecentState.current_effect
      DecentState.current_effect = nil
      @notify.call
      DecentState.current_effect = previous_effect
    end

    def cleanup
      until @dependencies.length == 0
        @dependencies.first&.remove_observer self
      end
    end

    attr_reader :dependencies
  end

  class DerivedState < State
    def initialize(&computation)
      super nil

      @effect = DecentState::Effect.new do
        self.value = computation.call
      end
    end

    def cleanup
      super
      @effect.cleanup
    end
  end

  class Scope
    def initialize(&scope)
      @parent_scope = DecentState.current_scope
      @child_scopes = []
      @computations = []

      @parent_scope&.child_scopes&.push self
      capture &scope
    end

    def capture
      previous_scope = DecentState.current_scope
      DecentState.current_scope = self
      yield
      DecentState.current_scope = previous_scope
    end

    def cleanup
      until @computations.length == 0
        @computations.last&.cleanup
        @computations.pop
      end

      until @child_scopes.length == 0
        @child_scopes.last&.cleanup
      end

      @parent_scope&.child_scopes&.delete self
    end

    attr_reader :child_scopes, :computations
  end

  def scope(&scope)
    Scope.new &scope
  end

  def state(initial = nil)
    State.new initial
  end

  def derived(&computation)
    DerivedState.new(&computation)
  end

  def effect(dependencies = nil, &notifier)
    Effect.new dependencies, &notifier
  end

  def unwrap_state(obj)
    obj.is_a?(State) ? obj.value : obj
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