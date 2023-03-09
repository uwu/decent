# frozen_string_literal: true
require "observer"
require "set"

# todo: MOVE AWAY FROM OBSERVABLES! currently decent only works in truffle due to a (much better) differing implementation of Ruby observables

module Decent
  class Watcher
    def initialize(&effect)
      @effect = effect
    end

    def update(*args)
      @effect.call(*args)
    end
  end

  class RefVisited
    include Observable

    def trigger(visited)
      changed
      notify_observers(visited)
    end
  end

  @visit_watcher = RefVisited.new

  def self.visit_watcher
    @visit_watcher
  end

  class Ref
    include Observable

    def initialize(initial)
      @value = initial
    end

    def value
      Decent.visit_watcher.trigger(self)
      @value
    end

    def value=(new_value)
      return if new_value == @value

      old_value = @value
      @value = new_value
      changed
      notify_observers(new_value, old_value)
    end
  end

  def ref(initial)
    Ref.new initial
  end

  class Effect
    def initialize(&watcher)
      @watched_refs = Set[]
      @watcher = watcher

      Decent.visit_watcher.add_observer(self)
      call_watcher
    end

    def call_watcher
      @watched_refs.each do |ref, effect|
        ref.delete_observer effect
      end

      @watched_refs = Set[]
      @watching = true
      @watcher.call
      @watching = false
    end

    def update(watched)
      if @watching
        effect = Watcher.new do
          call_watcher
        end

        watched.add_observer effect
        @watched_refs << [watched, effect]
      end
    end
  end

  def effect(&watcher)
    Effect.new &watcher
  end

  def derived(&watcher)
    sig = ref nil

    effect do
      sig.value = watcher.call
    end

    sig
  end
end