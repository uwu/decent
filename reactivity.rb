# frozen_string_literal: true
require "set"

module Decent
  # todo: make this observable implementation less mediocre
  module Signal
    def add_observer(observer)
      @observers ||= []
      @observers << observer
    end

    def delete_observer(observer)
      @observers&.delete(observer)
    end

    def unsubscribe_all
      @observers = []
    end

    def notify_observers(*args)
      @observers&.each do |observer|
        observer.call(*args)
      end
    end
  end

  class RefVisited
    include Signal

    def trigger(visited)
      notify_observers(visited)
    end
  end

  @visit_watcher = RefVisited.new

  def self.visit_watcher
    @visit_watcher
  end

  class Ref
    include Signal

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


  class Effect
    def initialize(dependencies = nil, &effect)
      # todo: maybe at some point add a simple handler when there's only one dependency?
      # hyper-autistic optimization might be important idk i'm just some retard on the internet

      if dependencies
        # not worth making a brand new set for no reason if the dependency list isn't going to change, dynamic types go brrr
        @dependencies = dependencies
        @fire_effect = effect

        dependencies.each do |dep|
          dep.add_observer effect
        end

        return
      end

      @dependencies = Set[]
      @watcher = ->(visited) { @dependencies << visited }
      @fire_effect = ->(_, _) { fire_effect }
      @effect = effect

      

      fire_effect
    end

    def fire_effect
      @dependencies.each do |dependency|
        dependency.delete_observer @fire_effect
      end

      @dependencies = Set[]
      Decent.visit_watcher.add_observer(@watcher)
      @effect.call
      Decent.visit_watcher.delete_observer(@watcher)

      @dependencies.each do |dependency|
        dependency.add_observer @fire_effect
      end
    end

    def unsubscribe_all
      @dependencies.each do |dependency|
        dependency.delete_observer @fire_effect
      end

      @dependencies = Set[]
    end
  end
end