# frozen_string_literal: true

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

      text.split("\n").each_with_index do |line, index|
        @stdout.print("\033[#{y + index + 1 };#{x}H#{line}")
      end
    end

    def size
      # this returns an array with the amount of cols and rows in the terminal, not the coordinates for top left and bottom right!!!
      @stdout.winsize.reverse
    end

    def clear
      # print "\033[0;0H#{" " * @furthest}"
      # @furthest = 0

      # todo: switch this out for the @furthest implementation. or something cooler. knowing UWUNET this will be
      # swapped out for something much more sane. i am not sane.
      @stdout.print "\033[2J"
    end
  end
end