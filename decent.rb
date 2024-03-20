require_relative "state"

module Decent
  extend DecentState

  def self.app(&ui)
    Decent.new(&ui)
  end

  class TreeNode
    include DecentState

    def initialize(attributes = {})
      @parent = self
      @children = []
      @unloadables = [] # storing Unloadables for when removing the node from the tree
      @attributes = attributes
    end

    def remove
      @unloadables.each(&:cleanup)
      @children.each(&:remove)

      @parent.children.delete(self) unless @parent == self
    end

    def append_child(node)
      @children.push node
      node.remove unless node.parent == node
      node.parent = self
    end

    attr_reader :children
    attr_accessor :parent, :unloadables

    def attributes
      unwrap_hash(@attributes)
    end

    def split_attributes
      @attributes.each_pair.filter_map {|key, val| [key, val] if is_state? val }.to_h
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

  class Decent
    include DecentState

    def create_node(type = TreeNode, attributes = {}, before_draw: ->{}, &ui)
      node = type.new(attributes)
      @current_node.append_child node
      @current_node = node
      node.unloadables.push(
        scope do
          instance_eval(&ui)

          effect node.split_attributes.values do
            before_draw.call(node)
            @root.draw
          end
        end
      )

      @current_node = node.parent
    end

    def initialize(root = RootNode.new, &ui)
      @root = root
      @current_node = @root

      instance_eval(&ui)
    end
  end
end

