#require "debug/open"

require_relative "decent_tui"

Decent.tui do
  count = state 10
  w = state 1.0

  box(width: w) {
    label derived { count.value.to_s }
  }

  box(width: 5) {
    label "abc"
  }

  stack {
    box(height: w) {
      label "layouting hehe"
    }
    box {}
  }

  dw = 0.5

  queue_task do
    Thread.new do
      loop do
        count.value -= 1
        w.value += dw

        if w.value > 2
          dw = -0.1
        elsif w.value < 0.5
          dw = 0.1
        end

        # mruby for some reason hates it if i don't add this sleep call. i'll figure out why later probably lol
        sleep 0.0000000000000001
      end
    end
  end
end