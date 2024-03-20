require_relative "decent_tui"

Decent.tui do
  count = state 0.1

  box {
    box {
      box {
        stack {
          flow {
            box(width: count) {}
            box {}
          }
          flow {
            box(height:count) {}

            box {}
          }
        }
      }
      box {
        label derived { "Woah! It's currently at: #{count.value.to_s}" }
      }
    }
  }


  Thread.new do
    flip = true

    loop do
      if flip
        count.value += 0.1
      else
        count.value -= 0.1
      end

      if count.value >= 2.0
        flip = false
      elsif count.value <= 0.1
        flip = true
      end
    end
  end
end