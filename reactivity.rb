# frozen_string_literal: true
require "set"

module Decent
  # todo: make this observable implementation less mediocre
  module Observable
    def add_observer(observer)
      @observers ||= []
      @observers << observer
    end

    def delete_observer(observer)
      @observers&.delete(observer)
    end

    def notify_observers(*args)
      @observers&.each do |observer|
        observer.update(*args)
      end
    end
  end

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

  def effect(dependencies = nil, &watcher)
    return Effect.new(&watcher) if dependencies.nil?

    dependencies.each do |dependency|
      dependency.add_observer Watcher.new(&watcher)
    end
  end

  def derived(&watcher)
    sig = ref nil

    effect do
      sig.value = watcher.call
    end

    sig
  end
end