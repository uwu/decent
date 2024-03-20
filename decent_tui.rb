require "io/console"
require_relative "decent"

module Decent
  class TerminalNode < TreeNode
    def initialize(*args)
      super(*args)

      @dirty = true
      @calculated_size = [0, 0]
      @constraints = @calculated_size
      @cache = ""
    end

    def render
      return @cache unless dirty

      @dirty = false

      layout_children
      @cache = render_children
    end

    def width
      attributes[:width] || 1.0
    end

    def height
      attributes[:height] || 1.0
    end

    def is_stack?
      self.class == StackNode
    end

    # This accounts for layouting.
    def layout_children
      absolute_widths, fraction_widths = @children.partition { _1.width.is_a? Integer }
      absolute_heights, fraction_heights = @children.partition { _1.height.is_a? Integer }

      available_width = is_stack? ? constraints[0] : (@constraints[0] - absolute_widths.map { _1.width }.sum)
      available_height = is_stack? ? (@constraints[1] - absolute_heights.map {_1.height }.sum) : constraints[1]

      widths = fraction_widths.map { _1.width }
      heights = fraction_heights.map { _1.height }

      resolved_width = is_stack? ? (widths.max || 0) : widths.sum
      resolved_height = is_stack? ? heights.sum : (heights.max || 0)

      fraction_widths.each_with_index do |node, idx|
        width = node.width

        size = (available_width * width / resolved_width)

        if node.calculated_size[0] != size
          node.dirty = true

          node.calculated_size[0] = size
          node.constraints[0] = size
        end
      end

      fraction_heights.each_with_index do |node, idx|
        height = node.height

        size = (available_height * height / resolved_height)

        if node.calculated_size[1] != size
          node.dirty = true

          node.calculated_size[1] = size
          node.constraints[1] = size
        end
      end

      absolute_widths.each do |node|
        width = node.width

        if node.calculated_size[0] != width
          node.dirty = true

          node.calculated_size[0] = width
          node.constraints[0] = width
        end
      end

      absolute_heights.each do |node|
        height = node.height

        if node.calculated_size[1] != height
          node.dirty = true

          node.calculated_size[1] = height
          node.constraints[1] = height
        end
      end
    end

    def render_children
      # This is implicitly a stack, I guess!
      rendered = @children.map(&:render)

      return "" if rendered.length == 0

      if is_stack?
        rendered.join "\n"
      else
        child_lines = rendered.map { _1.lines(chomp: true) }
        max_height = child_lines.map(&:length).max

        child_lines.each do |lines|
          (max_height - lines.length).times do
            lines.push " " * lines.last.length
          end
        end

        child_lines[0].zip(*child_lines[1..-1]).map(&:join).join("\n")
      end
    end

    attr_accessor :calculated_size, :dirty, :constraints
  end

  class TerminalRoot < TerminalNode
    def initialize(renderer)
      super

      @calculated_size = renderer.size.reverse
      @constraints = @calculated_size

      @renderer = renderer
    end

    def draw
      @renderer.draw(render, 0, 0)
      @renderer.render
    end

    def is_root?
      true
    end
  end

  class StackNode < TerminalNode

  end

  class FlowNode < TerminalNode

  end

  class BoxNode < TerminalNode
    def render
      return @cache unless @dirty

      # Width
      @constraints[0] = @calculated_size[0] - 2

      # Height
      @constraints[1] = @calculated_size[1] - 2

      layout_children

      width, height = @constraints
      box = ""

      box << "┌#{'─' * width}┐\n"
      box << "│#{' ' * width}│\n" * height
      box << "└#{'─' * width}┘"

      box_lines = box.lines

      render_children.lines(chomp: true).each_with_index do |line, idx|
        box_lines[idx + 1][1..(line.length)] = line
      end

      @dirty = false
      @cache = box_lines.join
    end
  end

  class LabelNode < TerminalNode
    def render
      attributes[:content]
    end

    def height
      attributes[:content].lines(chomp: true).length
    end

    def width
      attributes[:content].lines(chomp: true).map(&:length).max
    end
  end

  class SpacerNode < TerminalNode
    def render
      width, height = @constraints
      ((" " * width + "\n") * height).chomp
    end
  end

  class DecentTUI < Decent
    def fr(num)
      num * 0.01
    end

    def create_node(*args, &ui)
      super(*args, before_draw: ->(node) {
        @root.dirty = true

        until node.is_root?
          node.dirty = true

          node = node.parent
        end
      }, &ui)
    end

    def box(width: 1.0, height: 1.0, &ui)
      create_node(BoxNode, {width:, height:}, &ui)
    end

    def stack(&ui)
      create_node(StackNode, {}, &ui)
    end

    def flow(&ui)
      create_node(FlowNode, {}, &ui)
    end

    def label(content)
      create_node(LabelNode, {content:}) {}
    end

    def spacer
      create_node(SpacerNode, {}) {}
    end

    def center(&ui)
      spacer
      ui.call
      spacer
    end

    def initialize(stdout, &ui)
      @renderer = TerminalRenderer.new(stdout)
      @renderer.setup

      root = TerminalRoot.new(@renderer)
      super root, &ui

      root.draw

      begin
        loop {}
      ensure
        @renderer.cleanup
      end
    end
  end

  def self.tui(stdout = STDOUT, &ui)
    DecentTUI.new(stdout, &ui)
  end

  class TerminalRenderer
    def initialize(stdout = STDOUT)
      @stdout = stdout
      @buffer = [] # unnecessary, gives type-hints to IDE

      clear

      @previous_buffer = @buffer
    end

    def setup
      @stdout.print "\033[?1049h" # Save screen
      @stdout.print "\033[2J" # Clear screen
      @stdout.print "\033[?25l" # Disable cursor
    end

    def cleanup
      @stdout.print "\033[2J" # Clear screen
      @stdout.print "\033[?25h" # Re-enable cursor
      @stdout.print "\033[?1049l" # Restore screen
    end

    # Draw takes starting coordinates and draws text to the current screen buffer.
    # Draw does *not* render the current buffer to the terminal.
    def draw(text = "", x = 0, y = 0)
      text.each_line(chomp: true).each_with_index do |line, y_offset|
        line.each_char.each_with_index do |char, x_offset|
          @buffer[y + y_offset][x + x_offset] = char
        end
      end
    end

    # Render takes the current screen buffer and renders it to the terminal.
    def render
      @stdout.print "\033[0;0f"

      @buffer.each do |line|
        @stdout.print line.join("")
      end
    end

    def clear
      @buffer = Array.new(size[0]) { Array.new(size[1]) { " " } }
    end

    # Gets the terminal size, index 0 is rows, index 1 is columns.
    def size
      @stdout.winsize
    end
  end
end