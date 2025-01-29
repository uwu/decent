require_relative "state"

module Decent
  extend DecentState

  def self.app(&ui)
    DecentInternal.new(&ui)
  end

  class TreeNode
    include DecentState

    def initialize(attributes = {})
      @parent = self
      @children = []
      @reactivity_scope = scope {}
      @attributes = attributes
      @app = nil
    end

    def walk(&block)
      @children.each do |child|
        block.call child
        child.walk &block
      end
    end

    def remove
      @parent.remove_child(self)
    end

    def remove_child(node)
      return node.remove if node.parent != self

      @children.delete node

      node.reactivity_scope.cleanup

      until node.children.length == 0
        node.remove_child node.children.last
      end
    end

    def remove_children
      @children.each { _1.reactivity_scope.cleanup }
      @children = []
    end

    def append_child(node)
      @children.push node

      node.parent = self
    end

    attr_accessor :parent, :app, :reactivity_scope, :root

    def children
      @children.reduce([]) do |prev, child|
        if child.is_a? FragmentNode
          prev + child.children
        else
          [*prev, child]
        end
      end
    end

    def children=(value)
      @children = value
    end

    def attributes
      unwrap_hash(@attributes)
    end

    def split_attributes
      @attributes.each_pair.filter_map { |key, val| [key, val] if val.is_a? State }.to_h
    end

    def draw # This exists exclusively for type hinting.
      throw "You must override this method to have it act as a root node."
    end

    def is_root?
      false
    end
  end

  class RootNode < TreeNode
    def is_root?
      true
    end
  end

  class FragmentNode < TreeNode
    def method_missing(name, *args)
      @parent.send(name, *args) unless @parent == self
    end
  end

  class DecentInternal
    include DecentState

    def initialize(root = RootNode.new, &ui)
      @root = root
      @current_node = @root
      @batching = false
      @attributes_dirty = false

      instance_eval(&ui)
    end

    attr_accessor :root

    def frag(&ui)
      create_node(FragmentNode, {}, &ui)
    end

    def show(on:, &ui)
      node = FragmentNode.new

      build_ui = ->(initial = false) {
        node.remove_children

        if on.value
          build_in_node(node, &ui)
        end

        node.update unless initial

        batch do
          @attributes_dirty = true
        end
      }

      node.reactivity_scope.capture {
        effect([on], &build_ui)
      }

      @current_node.append_child node

      build_ui.call true
    end

    def each(of:, &builder)
      parent_node = FragmentNode.new

      build_node = ->(item) {
        built_frag = FragmentNode.new
        built_frag.parent = parent_node

        build_in_node(built_frag) do
          builder.call(item)
        end

        built_frag
      }

      nodes = []

      run_effect = -> {
        # Cleanup nodes that have been removed from the array
        nodes.each do |(item, node)|
          next if of.untracked.find { _1.equal? item }

          node.reactivity_scope.cleanup
        end

        nodes = of.untracked.map do |item|
          found = nodes.find { |(i, _)| i.equal? item }

          found || [item, build_node.call(item)]
        end

        parent_node.children = nodes.map { _1[1] }
        parent_node.update

        batch do
          @attributes_dirty = true
        end
      }

      parent_node.reactivity_scope.capture do
        effect([of], &run_effect)
      end

      @current_node.append_child parent_node
      run_effect.call
    end

    def before(name, &hook)
      original = @current_node.method(name)

      @current_node.define_singleton_method(name) do |*args, &block|
        hook.call(*args)

        original.call(*args, &block)
      end
    end

    def after(name, &hook)
      original = @current_node.method(name)

      @current_node.define_singleton_method(name) do |*args, &block|
        result = original.call(*args, &block)

        hook.call(*args)
        result
      end
    end

    alias_method :on, :after

    def batch(&block)
      was_batching = @batching
      @batching = true
      block&.call

      unless was_batching
        @root.draw if @attributes_dirty
        @attributes_dirty = false
        @batching = false
      end
    end

    def create_node(type = TreeNode, attributes = {}, &ui)
      node = type.new(attributes)
      node.app = self
      @current_node.append_child node
      @current_node = node

      node.reactivity_scope.capture do
        instance_eval(&ui) unless ui.nil?

        # this creates a ton of effects but i think that's okay?
        effect node.split_attributes.values do
          node.update

          batch do
            @attributes_dirty = true
          end
        end
      end

      @current_node = node.parent
      node
    end

    def build_in_node(node, &builder)
      previous_node = @current_node
      @current_node = node
      node.reactivity_scope.capture do
        # Ensure reactivity is coupled to the node
        builder.call
      end
      @current_node = previous_node
    end
  end
end
