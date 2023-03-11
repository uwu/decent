require "./decent.rb"

app = Decent::App.new do
  w = ref 10

  box do
    box width: w do
      box do
        text derived { "Hi!" * w.value }
      end
    end
  end

  Thread.new do
    loop do
      if w.value > 30
        w.value = 10
      else
        w.value += 1
      end
    end
    sleep 1
  end
end

app.run
