require_relative "decent"
require "io/console"
require "async"
require "async/io/stream"

module Decent
  class StringBuf
    def initialize(size)
      len = size[0] * size[1]
      @size = size # [w, h]
      @charbuf = Array.new(len, 32) # space char
      @stylemap_fgcol = Array.new(len, 39) # default fg col
      @stylemap_bgcol = Array.new(len, 49)
      @stylemap_sgr   = Array.new(len) { Array.new }
    end

    # i stg do not edit the arrays returned by these or i will murder you -- sink
    attr_reader :size, :charbuf, :stylemap_bgcol, :stylemap_fgcol, :stylemap_sgr

    # parse a multiline string into a stringbuf
    # note: assumes there are no double-wide characters. these will not be correctly handled.
    # however, it DOES correctly handle graphemes.
    def parse(str)
      split = str.split "\n"
      width = split.max { |a, b| a.each_grapheme_cluster.size <=> b.each_grapheme_cluster.size }

      dest = StringBuf.new [width, split.length]
      split.each_with_index do |line, y|
        line.each_grapheme_cluster.each_with_index do |grapheme, x|
          dest[[x, y]] = grapheme
        end
      end
    end

    def __resolve(pos) # [x, y]
      if pos[0] >= size[0] || pos[1] >= size[1]
        throw Exception.new "Index out of range while indexing Decent::StringBuf"
      end

      pos[0] + (pos[1] * @size[1])
    end

    def [](pos)
      c = @charbuf[__resolve pos]
      if c.is_a? Integer
        return c.chr Encoding::UTF_8
      end
      # c is an integer array (grapheme cluster)
      c.map { |chr| chr.chr Encoding::UTF_8  }.join
    end

    def []=(pos, val)
      # assume that if the string has multiple characters, we should treat it as a grapheme cluster
      if val.length == 0
        @charbuf[__resolve pos] = []
      elsif val.length == 1
        @charbuf[__resolve pos] = val.ord
      else
        @charbuf[__resolve pos] = val.codepoints
      end
    end

    def get_fg(pos)
      @stylemap_fgcol[__resolve pos]
    end
    def get_bg(pos)
      @stylemap_bgcol[__resolve pos]
    end
    def get_sgr(pos)
      @stylemap_sgr[__resolve pos]
    end

    def set_fg(pos, col)
      @stylemap_fgcol[__resolve pos] = col
    end
    def set_bg(pos, col)
      @stylemap_bgcol[__resolve pos] = col
    end
    def set_sgr(pos, sgr)
      @stylemap_sgr[__resolve pos] = sgr
    end

    def resize(new_size)
      new = StringBuf.new new_size
      new.template(self, [0, 0])
      new
    end

    def resize!(new_size)
      # let the GC collect the old arrays and the new class WHEEEE
      new = resize new_size
      @charbuf = new.charbuf
      @stylemap_fgcol = new.stylemap_fgcol
      @stylemap_bgcol = new.stylemap_bgcol
      @stylemap_sgr = new.stylemap_sgr
    end

    def template(str, pos, clip = nil)
      if clip == nil
        # no max size given, just use the string size
        clip = str.size
      else
        # make clip the min of the allowable space and the size of the string we're templating
        clip = [min(clip[0], str.size[0] - pos[0]), min(clip[1], str.size[1] - pos[1])]
      end

      # ensure we don't overdraw
      clip = [min(clip[0], @size[0]), min(clip[1], @size[1])]

      clip[1].times do |y|
        clip[0].times do |x|
          ox = x + pos[0]
          oy = y + pos[1]
          srcidx = str.__resolve [x, y]
          dstidx = __resolve [ox, oy]

          @charbuf[dstidx] = str.charbuf[srcidx]
          @stylemap_fgcol[dstidx] = str.stylemap_fgcol[srcidx]
          @stylemap_bgcol[dstidx] = str.stylemap_bgcol[srcidx]
          @stylemap_sgr[dstidx] = str.stylemap_sgr[srcidx]
        end
      end
    end
  end

  # this is what you hand down to children to abstract positioning from them and make sure they behave themselves
  class StringTemplater
    def initialize(str, pos, size)
      @str = str
      @pos = pos
      @clip = size
    end

    attr_accessor :pos, :clip

    def __offset(pos)
      [pos[0] + @pos[0], pos[1] + @pos[1]]
    end

    def [](pos)
      @str[__offset pos]
    end

    def []=(pos, val)
      @str[__offset pos] = val
    end

    def template(str, pos)
      @str.template str, __offset(pos), @clip
    end

    def sub_templater(pos, clip)
      oset_clip = __offset clip
      # bounds check
      oset_clip = [min(oset_clip[0], @str.size[0]), min(oset_clip[1], @str.size[1])]

      StringTemplater.new @str, __offset(pos), oset_clip
    end
  end

  class TerminalNode < TreeNode
    def initialize(*args)
      super(*args)

      @dirty = true
      @calculated_size = [0, 0]
      @constraints = reactive({ width: @calculated_size[0], height: @calculated_size[1] })
      # @templater = nil
      #@cache = ""
    end

    def render
      return unless dirty

      @dirty = false

      layout_children
      #@cache =
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
      return if children.length == 0

      if is_stack?
        used_space = 0
        children.each do |c|
          oset = is_stack? ? [0, used_space] : [used_space, 0]

          c.templater = @templater.sub_templater oset, c.calculated_size
          c.render

          used_space += c.calculated_size[is_stack? ? 1 : 0]
        end
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
      return unless @dirty
      puts "hi"

      # Width
      @constraints.width = @calculated_size[0] - 2

      # Height
      @constraints.height = @calculated_size[1] - 2

      layout_children

      wmax = @calculated_size[0] - 1
      hmax = @calculated_size[1] - 1

      @templater[[0, 0]] = "┌"
      @templater[[wmax, 0]] = "┐"
      @templater[[0, hmax]] = "└"
      @templater[[wmax, hmax]] = "┘"

      (@calculated_size[0] - 2).times do |i|
        @templater[[i + 1, 0]] = "─"
        @templater[[i + 1, hmax]] = "─"
      end
      (@calculated_size[1] - 2).times do |i|
        @templater[[0, i + 1]] = "│"
        @templater[[wmax, i + 1]] = "│"
      end

      # lmao
      old_templater = @templater

      @templater = @templater.sub_templater [1, 1], [@templater.buf.size[0] - 2, @templater.buf.size[1] - 2]
      render_children

      @templater = old_templater

      @dirty = false
      #@cache = box
    end
  end

  class LabelNode < TerminalNode
    def render
      @templater.template StringBuf.parse(attributes[:content]), [0, 0]
    end

    def height
      attributes[:content].lines(chomp: true).length
    end

    def width
      attributes[:content].lines(chomp: true).map { | l | l.each_grapheme_cluster.size }.max
    end
  end

  class SpacerNode < TerminalNode
    def render
      return unless @dirty
      width = @constraints.width
      height = @constraints.height
      height.times do |y|
        width.times do |x|
          @templater[[x, y]]
        end
      end
      @dirty = true
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

        return

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
      # @buffer = nil
    end

    def setup
      #@stdout.print "\033[?1049h" # Save screen
      #@stdout.print "\033[2J" # Clear screen
      @stdout.print "\033[?25l" # Disable cursor

      @stdin.echo = false

      clear
    end

    def cleanup
      @stdin.echo = true

      #@stdout.print "\033[2J" # Clear screen
      #@stdout.print "\033[?25h" # Re-enable cursor
      #@stdout.print "\033[?1049l" # Restore screen
    end

    # Draw takes starting coordinates and draws text to the current screen buffer.
    # Draw does *not* render the current buffer to the terminal.
=begin
    def draw(text = "", x = 0, y = 0)
      # TODO: This sucks, we *need* diffing
      text.each_line(chomp: true).each_with_index do |line, y_offset|
        line.each_char.each_with_index do |char, x_offset|
          @buffer[y + y_offset][x + x_offset] = char
        end
      end
    end
=end

    def clear
      sz = size
      @buffer = StringBuf.new [sz[1], sz[0]]
    end

    # Render takes the current screen buffer and renders it to the terminal.
    def render
      puts @buffer.charbuf

      # despite ruby being ruby, its probably faster to build this in memory anyway
      render_buffer = "\033[0;0f\033[39;49m"

      prev_fg = 39
      prev_bg = 49
      @buffer.size[1].times do |y|
        @buffer.size[0].times do |x|
          fg = @buffer.get_fg [x, y]
          bg = @buffer.get_bg [x, y]
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

          sgr = @buffer.get_sgr [x, y]
          if sgr.length > 0
            render_buffer += "\033[" + sgr.map { |n| n.to_s }.join(";") + "m"
          end

          render_buffer += @buffer[[x, y]]
        end
        render_buffer += "\n"
      end

      @stdout.print render_buffer
      #clear
    end

    # Gets the terminal size, index 0 is rows, index 1 is columns.
    def size
      #@stdout.winsize
      [15, 15]
    end

    def root_templater
      StringTemplater.new @buffer, [0, 0], @buffer.size
    end
  end
end