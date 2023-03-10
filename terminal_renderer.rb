require "io/console"

module Decent
  class TerminalRenderer
    def initialize(stdout)
      @stdout = stdout
      @lastbuffer = []
      @buffer = []
      @lastsize = [-1, -1]
    end

    def setup
      # print ansi clear, all other clears should be handled by the clear() method that'll do magical wacky bullshit
      @stdout.print "\033[2J"
      @stdout.print("\033[?25l")
    end

    def cleanup
      @stdout.print("\033[?25h")
    end

    def draw(text, x = 0, y = 0)
      text.split("\n").each_with_index do |line, iy|
        line.each_char.with_index do |c, ix|

          while @buffer.length <= (iy + y)
            @buffer.push ""
          end

          while @buffer[iy + y].length <= (ix + x)
            @buffer[iy + y] += " "
          end

          @buffer[iy + y][ix + x] = c
        end
      end

      # TODO: right padding can be done in this loop probably

      #@buffer += text.split("\n").map.with_index {|line, index| "\033[#{y + index + 1 };#{x + 1}H#{line}" }.join
    end

    def render
      renderbuffer = []
      @buffer.each_with_index do |line, idx|
         renderbuffer.push line.ljust(@lastbuffer[idx]&.length || 0)
      end

      @stdout.print "\033[;1H" + renderbuffer.join

      @lastbuffer = @buffer
    end

    def size
      # this returns an array with the amount of cols and rows in the terminal, not the coordinates for top left and bottom right!!!
      newsize = @stdout.winsize.reverse

      if (newsize != @lastsize)
        @lastsize[0] = newsize[0]
        @lastsize[1] = newsize[1]
        @buffer = []
        @lastbuffer = []
        @stdout.print "\033[;1H\033[2J"
      end

      newsize
    end

    def clear
      @buffer = []
    end
  end
end
