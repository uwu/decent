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
      @unloadables = [] # storing Unloadables for when removing the node from the tree
      @attributes = attributes
      @app = app
    end

    def cleanup
      @unloadables.each(&:cleanup)
      @unloadables = [] # unnecessary but whatever

      @children.each do |c|
        c.cleanup
      end
    end

    def walk(&block)
      @children.each(&:walk &block)
    end

    def remove
      @parent.remove_child(self)
    end

    def remove_child(node)
      return node.remove if node.parent != self

      @children.delete node

      node.cleanup

      until node.children.length == 0
        node.remove_child node.children[0]
      end
    end

    def remove_children
      until @children.length == 0
        @children[0].remove
      end
    end

    def append_child(node)
      @children.push node

      node.parent = self
    end

    attr_accessor :parent, :unloadables, :app

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
      @attributes.each_pair.filter_map { |key, val| [key, val] if is_state? val }.to_h
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
      @parent.send(name, *args)
    end
  end

  class DecentInternal
    include DecentState

    def initialize(root = RootNode.new, node_type = TreeNode, &ui)
      @root = root
      @current_node = @root
      @prevent_drawing = false

      instance_eval(&ui)
    end

    def frag(&ui)
      create_node(FragmentNode, {}, &ui)
    end

    def show(on:, &ui)
      node = FragmentNode.new
      cleanup_prev = nil

      node.unloadables.push(Unloadable.new(node.unloadables) {
        cleanup_prev&.cleanup
      })

      build_ui = -> {
        node.remove_children
        cleanup_prev&.cleanup

        if on.value
          cleanup_prev = scope do
            build_in_node(node, &ui)
          end
        end

        node.update

        unless @prevent_drawing
          prevent_drawing do
            @root.draw
          end
        end
      }

      node.unloadables.push(effect([on], &build_ui))
      @current_node.append_child node
      build_ui.call
    end

    def each(of:, &builder)
      parent_node = FragmentNode.new

      build_node = ->(item) {
        built_frag = FragmentNode.new
        built_frag.parent = parent_node

        built_frag.unloadables.push(scope {
          build_in_node(built_frag) do
            builder.call(item)
          end
        })

        built_frag
      }

      nodes = []

      run_effect = -> {
        nodes.each do |(item, node)|
          next if of.untracked.find { _1.equal? item }

          node.cleanup
          node.children = []
        end
        nodes = of.untracked.map do |item|
          found = nodes.find {|(i, _)| i.equal? item }

          found ? found : [item, build_node.call(item)]
        end

        parent_node.children = nodes.map { _1[1] }
        parent_node.update

        unless @prevent_drawing
          prevent_drawing do
            @root.draw
          end
        end
      }

      parent_node.unloadables.push(
        effect([of], &run_effect)
      )

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

    def prevent_drawing
      @prevent_drawing = true
      yield
      @prevent_drawing = false
    end

    def create_node(type = TreeNode, attributes = {}, &ui)
      node = type.new(attributes)
      @current_node.append_child node
      @current_node = node

      node.unloadables.push(
        scope do
          instance_eval(&ui)

          effect node.split_attributes.values do
            node.update

            unless @prevent_drawing
              prevent_drawing do
                @root.draw
              end
            end
          end
        end
      )

      @current_node = node.parent
      node
    end

    def build_in_node(node, &builder)
      previous_node = @current_node
      @current_node = node
      builder.call
      @current_node = previous_node
    end
  end
end
