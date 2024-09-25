require_relative "decent"
require "io/console"
require "async"
require "async/io/stream"

module Decent
  class StringBuf
    def initialize(size)
      len = size[0] * size[1]
      @size = size # [w, h]
      @char_buf = Array.new(len, 32) # space char
      @stylemap_fgcol = Array.new(len, 39) # default fg col
      @stylemap_bgcol = Array.new(len, 49)
      @stylemap_sgr = Array.new(len) { Array.new }
    end

    # i stg do not edit the arrays returned by these or i will murder you -- sink
    attr_reader :size, :char_buf, :stylemap_bgcol, :stylemap_fgcol, :stylemap_sgr

    # parse a multiline string into a stringbuf
    # note: assumes there are no double-wide characters. these will not be correctly handled.
    # however, it DOES correctly handle graphemes.
    def self.parse(str)
      split = str.split "\n"
      width = split.map { |s| s.each_grapheme_cluster.size }.max
      dest = StringBuf.new [width, split.length]

      split.each_with_index do |line, y|
        line.each_grapheme_cluster.each_with_index do |grapheme, x|
          dest[x, y] = grapheme
        end
      end

      dest
    end

    # this was supposed to be private
    def resolve(x, y)
      # [x, y]
      if x >= size[0] || y >= size[1]
        throw Exception.new "Index out of range while indexing Decent::StringBuf"
      end

      x + (y * @size[0])
    end

    def [](x, y)
      c = @char_buf[resolve(x, y)]
      if c.is_a? Integer
        return c.chr Encoding::UTF_8
      end
      # c is an integer array (grapheme cluster)
      c.map { |chr| chr.chr Encoding::UTF_8 }.join
    end

    def []=(x, y, val)
      # assume that if the string has multiple characters, we should treat it as a grapheme cluster
      if val.length == 0
        @char_buf[resolve(x, y)] = []
      elsif val.length == 1
        @char_buf[resolve(x, y)] = val.ord
      else
        @char_buf[resolve(x, y)] = val.codepoints
      end
    end

    def get_fg(x, y)
      @stylemap_fgcol[resolve(x, y)]
    end

    def get_bg(x, y)
      @stylemap_bgcol[resolve(x, y)]
    end

    def get_sgr(x, y)
      @stylemap_sgr[resolve(x, y)]
    end

    def set_fg(x, y, col)
      @stylemap_fgcol[resolve(x, y)] = col
    end

    def set_bg(x, y, col)
      @stylemap_bgcol[resolve(x, y)] = col
    end

    def set_sgr(x, y, sgr)
      @stylemap_sgr[resolve(x, y)] = sgr
    end

    def resize(new_size)
      new = StringBuf.new new_size
      new.template(self, [0, 0])
      new
    end

    def clear!(start = [0, 0], size = @size)
      xs = start[0]
      ys = start[1]

      size[1].times do |y|
        size[0].times do |x|
          idx = resolve(xs + x, ys + y)
          @char_buf[idx] = 32
          @stylemap_fgcol[idx] = 39
          @stylemap_bgcol[idx] = 49
          @stylemap_sgr[idx].clear
        end
      end
    end

    def resize!(new_size)
      # let the GC collect the old arrays and the new class WHEEEE
      new = resize new_size
      @char_buf = new.char_buf
      @stylemap_fgcol = new.stylemap_fgcol
      @stylemap_bgcol = new.stylemap_bgcol
      @stylemap_sgr = new.stylemap_sgr
    end

    def template(str, pos, clip_size = nil)
      if clip_size == nil
        # no max size given, just use the string size
        clip_size = str.size
      else
        # make clip the min of the allowable space and the size of the string we're templating
        clip_size = [
          [clip_size[0], str.size[0]].min,
          [clip_size[1], str.size[1]].min
        ]
      end

      # ensure we don't overdraw
      clip_size = [
        [clip_size[0], @size[0]].min,
        [clip_size[1], @size[1]].min
      ]

      clip_size[1].times do |y|
        clip_size[0].times do |x|
          ox = x + pos[0]
          oy = y + pos[1]
          source_index = str.resolve(x, y)
          dest_index = resolve(ox, oy)

          @char_buf[dest_index] = str.char_buf[source_index]
          @stylemap_fgcol[dest_index] = str.stylemap_fgcol[source_index]
          @stylemap_bgcol[dest_index] = str.stylemap_bgcol[source_index]
          @stylemap_sgr[dest_index] = str.stylemap_sgr[source_index]
        end
      end
    end
  end

  # this is what you hand down to children to abstract positioning from them and make sure they behave themselves
  class StringTemplater
    def initialize(str, pos, size)
      @str = str
      @pos = pos
      @size = size
    end

    attr_accessor :pos, :size

    def width
      @str.size[0]
    end

    def height
      @str.size[1]
    end

    def offset(x, y)
      [
        x + @pos[0],
        y + @pos[1]
      ]
    end

    def [](x, y)
      @str[*offset(x, y)]
    end

    def []=(x, y, val)
      @str[*offset(x, y)] = val
    end

    def clear!
      @str.clear! @pos, @size
    end

    def template(str, pos)
      @str.template str, offset(*pos), @size
    end

    def sub_templater((x, y), (width, height))
      # bounds check
      size = [
        [width, @size[0] - x].min,
        [height, @size[1] - y].min
      ]

      StringTemplater.new @str, offset(x, y), size
    end
  end

  class TerminalNode < TreeNode
    def initialize(*args)
      super(*args)

      @dirty = true
      @calculated_size = [0, 0]
      @constraints = reactive({ width: @calculated_size[0], height: @calculated_size[1] })
    end

    def render
      @dirty = false

      layout_children
      render_children
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

      available_width = is_stack? ? @constraints.width : (@constraints.width - absolute_widths.map { _1.width }.sum)
      available_height = is_stack? ? (@constraints.height - absolute_heights.map { _1.height }.sum) : @constraints.height

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

    def render_children(templater = @templater)
      return if children.length == 0

      used_space = 0
      children.each do |c|
        offset = is_stack? ? [0, used_space] : [used_space, 0]

        c.templater = templater.sub_templater(offset, c.calculated_size)

        used_space += c.calculated_size[is_stack? ? 1 : 0]
      end

      children.each(&:render)
    end

    def with_bounds(&ui)
      @app&.build_in_node(self) do
        ui.call(@constraints)
      end
    end

    def update
      @dirty = true
    end

    attr_accessor :calculated_size, :dirty, :constraints, :templater
  end

  class TerminalRoot < TerminalNode
    def initialize(renderer)
      super

      @calculated_size = renderer.size.reverse
      @constraints = reactive({ width: @calculated_size[0], height: @calculated_size[1] })

      @renderer = renderer
      @templater = renderer.root_templater
    end

    def draw
      render
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
      @dirty = false

      # Width
      @constraints.width = @calculated_size[0] - 2

      # Height
      @constraints.height = @calculated_size[1] - 2

      layout_children

      right = @calculated_size[0] - 1
      bottom = @calculated_size[1] - 1

      @templater[0, 0] = "┌"
      @templater[right, 0] = "┐"
      @templater[0, bottom] = "└"
      @templater[right, bottom] = "┘"

      (@calculated_size[0] - 2).times do |i|
        @templater[i + 1, 0] = "─"
        @templater[i + 1, bottom] = "─"
      end

      (@calculated_size[1] - 2).times do |i|
        @templater[0, i + 1] = "│"
        @templater[right, i + 1] = "│"
      end

      render_children @templater.sub_templater [1, 1], [@templater.width - 2, @templater.height - 2]
    end
  end

  class LabelNode < TerminalNode
    def render
      return if attributes[:content].length == 0

      @templater.template StringBuf.parse(attributes[:content]), [0, 0]
    end

    def height
      attributes[:content].lines(chomp: true).length
    end

    def width
      attributes[:content].lines(chomp: true).map { |l| l.each_grapheme_cluster.size }.max || 0
    end
  end

  class SpacerNode < TerminalNode
    def render
      # return unless @dirty

      width = @constraints.width
      height = @constraints.height

      height.times do |y|
        width.times do |x|
          @templater[x, y] = " "
        end
      end

      @dirty = true
    end
  end

  class DecentTUI < DecentInternal
    def fr(num)
      num * 0.1
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

      -> { cleanups.each(&:call) }
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
      super root, &ui

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

                batch do
                  handler.call(mapped)
                end
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
      clear
      @root_templater = StringTemplater.new @buffer, [0, 0], [size[1], size[0]]
    end

    def setup
      @stdout.print "\033[?1049h" # Save screen
      @stdout.print "\033[2J" # Clear screen
      @stdout.print "\033[?25l" # Disable cursor

      @stdin.echo = false
    end

    def cleanup
      @stdin.echo = true

      @stdout.print "\033[2J" # Clear screen
      @stdout.print "\033[?25h" # Re-enable cursor
      @stdout.print "\033[?1049l" # Restore screen
    end

    def clear
      @buffer = StringBuf.new [size[1], size[0]]
    end

    # Render takes the current screen buffer and renders it to the terminal.
    def render
      # despite ruby being ruby, its probably faster to build this in memory anyway
      render_buffer = "\033[H\033[39;49m"

      prev_fg = 39
      prev_bg = 49
      @buffer.size[1].times do |y|
        @buffer.size[0].times do |x|
          fg = @buffer.get_fg(x, y)
          bg = @buffer.get_bg(x, y)
          if fg != prev_fg
            if bg != prev_bg
              render_buffer += "\033[" + fg.to_s + ";" + bg.to_s + "m"
            else
              # only fg
              render_buffer += "\033[" + fg.to_s + "m"
            end
          elsif bg != prev_bg
            # only bg
            render_buffer += "\033[" + bg.to_s + "m"
          end
          prev_fg = fg
          prev_bg = bg

          sgr = @buffer.get_sgr(x, y)
          if sgr.length > 0
            render_buffer += "\033[" + sgr.map { |n| n.to_s }.join(";") + "m"
          end

          render_buffer += @buffer[x, y]
        end
      end

      @stdout.print render_buffer
      @buffer.clear!
    end

    def size
      @stdout.winsize # [rows, columns]
    end

    attr_reader :root_templater
  end
end
