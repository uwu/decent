require_relative "decent"
require "io/console"
require "async"
require "async/io/stream"

module Decent
  class TerminalNode < TreeNode
    def initialize(*args)
      super(*args)

      @dirty = true
      @calculated_size = [0, 0]
      @constraints = reactive({ width: @calculated_size[0], height: @calculated_size[1] })
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
      absolute_widths, fraction_widths = children.partition { _1.width.is_a? Integer }
      absolute_heights, fraction_heights = children.partition { _1.height.is_a? Integer }

      available_width = is_stack? ? constraints.width : (@constraints.width - absolute_widths.map { _1.width }.sum)
      available_height = is_stack? ? (@constraints.height - absolute_heights.map { _1.height }.sum) : constraints.height

      widths = fraction_widths.map { _1.width }
      heights = fraction_heights.map { _1.height }

      resolved_width = is_stack? ? (widths.max || 0) : widths.sum
      resolved_height = is_stack? ? heights.sum : (heights.max || 0)

      remaining_width = available_width
      fraction_widths.each_with_index do |node, idx|
        width = node.width

        size = (available_width * width / resolved_width).floor
        unless is_stack?
          remaining_width -= size

          if idx == fraction_widths.length - 1
            size += remaining_width
          end
        end

        if node.calculated_size[0] != size
          node.dirty = true

          node.calculated_size[0] = size
          node.constraints.width = size
        end
      end

      remaining_height = available_height
      fraction_heights.each_with_index do |node, idx|
        height = node.height

        size = (available_height * height / resolved_height).floor
        if is_stack?
          remaining_height -= size

          if idx == fraction_heights.length - 1
            size += remaining_height
          end
        end

        if node.calculated_size[1] != size
          node.dirty = true

          node.calculated_size[1] = size
          node.constraints.height = size
        end
      end

      absolute_widths.each_with_index do |node, idx|
        width = node.width

        if node.calculated_size[0] != width
          node.dirty = true

          node.calculated_size[0] = width
          node.constraints.width = width
        end
      end

      absolute_heights.each do |node|
        height = node.height

        if node.calculated_size[1] != height
          node.dirty = true

          node.calculated_size[1] = height
          node.constraints.height = height
        end
      end
    end

    def render_children
      # This is implicitly a stack, I guess!
      rendered = children.map(&:render)

      return "" if rendered.length == 0

      if is_stack?
        rendered.join "\n"
      else
        child_lines = rendered.map { _1.lines(chomp: true) }
        max_height = child_lines.map(&:length).max

        # This adds missing vertical height to the rendered child to prevent collisions between child nodes.
        child_lines.each do |lines|
          (max_height - lines.length).times do
            if lines.length > 0
              lines.push " " * lines.last.length
            end
          end
        end

        child_lines.transpose.map(&:join).join("\n")
      end
    end

    def update
      node = self

      until node.is_root?
        node.dirty = true

        node = node.parent
      end

      node.dirty = true
    end

    attr_accessor :calculated_size, :dirty, :constraints
  end

  class TerminalRoot < TerminalNode
    def initialize(renderer)
      super

      @calculated_size = renderer.size.reverse
      @constraints = reactive({ width: @calculated_size[0], height: @calculated_size[1] })

      @renderer = renderer
    end

    def draw
      @renderer.draw(render)
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
      @constraints.width = @calculated_size[0] - 2

      # Height
      @constraints.height = @calculated_size[1] - 2

      layout_children

      width = @constraints.width
      height = @constraints.height

      child_lines = render_children.lines(chomp: true)

      (height - child_lines.length).to_i.times do
        child_lines.push("")
      end

      box = child_lines.map { |line| "│" + line + (" " * (width - line.length)) + "│" }.join("\n")
      box = "┌#{'─' * width}┐\n" + box + "\n└#{'─' * width}┘"

      @dirty = false
      @cache = box
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
      width = @constraints.width
      height = @constraints.height
      ((" " * width + "\n") * height).chomp
    end
  end

  class DecentTUI < DecentInternal
    def fr(num)
      num * 0.01
    end

    def box(width: 1.0, height: 1.0, &ui)
      create_node(BoxNode, { width:, height: }, &ui)
    end

    def stack(&ui)
      create_node(StackNode, {}, &ui)
    end

    def flow(&ui)
      create_node(FlowNode, {}, &ui)
    end

    def label(content)
      create_node(LabelNode, { content: }) {}
    end

    def spacer
      create_node(SpacerNode, {}) {}
    end

    def center(&ui)
      spacer
      ui.call
      spacer
    end

    def stop_queue
      @stop_queue = true
    end

    def queue_task(&cb)
      @queue.push(cb)
    end

    # Create a keyboard handler (rework later)
    def key(names = [], &callback)
      if names.is_a? String
        names = [names]
      end

      cleanups = names.map do |name|
        @keyboard_handlers[name] = [] unless @keyboard_handlers[name]

        handlers = @keyboard_handlers[name]
        handlers.push(callback)

        -> {
          handlers.delete_at(handlers.index(callback))
        }
      end

      Unloadable.new(-> { cleanups.each(&:call) })
    end

    def initialize(stdout, stdin, &ui)
      @renderer = TerminalRenderer.new(stdout, stdin)
      @renderer.setup
      @stop_queue = false
      @queue = []

      # This keymap is actually extremely primitive.
      @keymap = { "\r" => "Enter",
                  "\b" => "Backspace",
                  "\x7F" => "Backspace",
                  "^Q" => "\u0011",
                  "^W" => "\u0017",
                  "^E" => "\u0005",
                  "^R" => "\u0012",
                  "^T" => "\u0014",
                  "^Y" => "\u0019",
                  "^U" => "\u0015",
                  "^I" => "\t",
                  "^O" => "\u000F",
                  "^P" => "\u0010",
                  "^A" => "\u0001",
                  "^S" => "\u0013",
                  "^D" => "\u0004",
                  "^F" => "\u0006",
                  "^G" => "\a",
                  "^H" => "\b",
                  "^J" => "k",
                  "^\v" => "l",
                  "^\f" => "x",
                  "^\u0018" => "v",
                  "^B" => "\u0002",
                  "^N" => "\u000E",
                  "^[" => "\e",
                  "^]" => "\u001D" }
      @keyboard_handlers = { "*" => [] }

      root = TerminalRoot.new(@renderer)
      super root, TerminalNode, &ui

      begin
        root.draw

        # We can remove this after TruffleRuby gets support for Fiber schedulers.
        # This is why I wanted 0 deps. Sigh :(
        readable_stdin = Async::IO::Stream.new(
          Async::IO::Generic.new(stdin)
        )

        until @stop_queue
          Async do |task|
            task.async do
              stdin.raw!
              char = readable_stdin.read(1)
              stdin.cooked! # This method name is fucking dumb lmao.

              if char == "\x03"
                @stop_queue = true
              end

              mapped = @keymap[char] || char
              ((@keyboard_handlers[mapped] || []) + @keyboard_handlers["*"]).each do |handler|
                handler.call(mapped)
              end
            end

            task.async do
              @queue.each do
                task.async(&_1)
              end

              @queue = []
            end
          end
        end
      ensure
        @renderer.cleanup
      end
    end
  end

  def self.tui(stdout = STDOUT, stdin = $stdin, &ui)
    DecentTUI.new(stdout, stdin, &ui)
  end

  class TerminalRenderer
    def initialize(stdout = STDOUT, stdin = $stdin)
      @stdout = stdout
      @stdin = stdin
      @buffer = []

      @previous_buffer = @buffer
    end

    def setup
      @stdout.print "\033[?1049h" # Save screen
      @stdout.print "\033[2J" # Clear screen
      @stdout.print "\033[?25l" # Disable cursor

      @stdin.echo = false
      @stdout.sync = false

      clear
    end

    def cleanup
      @stdin.echo = true
      @stdout.sync = true

      @stdout.print "\033[2J" # Clear screen
      @stdout.print "\033[?25h" # Re-enable cursor
      @stdout.print "\033[?1049l" # Restore screen
    end

    # Draw takes starting coordinates and draws text to the current screen buffer.
    # Draw does *not* render the current buffer to the terminal.
    def draw(text = "", x = 0, y = 0)
      # TODO: This sucks, we *need* diffing
      text.each_line(chomp: true).each_with_index do |line, y_offset|
        line.each_char.each_with_index do |char, x_offset|
          @buffer[y + y_offset][x + x_offset] = char
        end
      end
    end

    def clear
      @buffer = Array.new(size[0]) { Array.new(size[1]) { " " } }
    end

    # Render takes the current screen buffer and renders it to the terminal.
    def render
      @stdout.print "\033[0;0f" + @buffer.map(&:join).join("\n")
      clear
      @stdout.flush
    end

    # Gets the terminal size, index 0 is rows, index 1 is columns.
    def size
      @stdout.winsize
    end
  end
end