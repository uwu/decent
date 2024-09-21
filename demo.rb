#require "debug/open"

require_relative "decent_tui"

Decent.tui do
  count = state 10

  box {
    label derived { count.value.to_s }
  }

  box {
    label "layouting hehe"
  }

  key "Enter" do
    count.value -= 1
  end

  # Thread.new do
  #   loop do
  #     count.value -= 1
  #   end
  # end
end
