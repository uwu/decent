# frozen_string_literal: true
require "io/console"

module Decent
  class TerminalRenderer
    def initialize(stdout)
      @stdout = stdout
      @furthest = 0
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
      padding = (x * y) + text.length # this does not account for the length of ansi escape codes, todo: fix this

      # this is likely bugged with the newline fixes i've just done below. oh well, more work for kasi!
      @furthest = padding > @furthest ? padding : @furthest

      @stdout.print text.split("\n").map.with_index {|line, index| "\033[#{y + index + 1 };#{x + 1}H#{line}" }.join
    end

    def size
      # this returns an array with the amount of cols and rows in the terminal, not the coordinates for top left and bottom right!!!
      @stdout.winsize.reverse
    end

    def clear
      # todo: make this not suck
      @stdout.print "\033[0;0H" + (" " * size.reduce(:*))
    end
  end
end