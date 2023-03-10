require "./decent.rb"

app = Decent::App.new do
  h = ref 3

  box do
    box height: h do
      text derived { "Hello world!" * h.value }
    end
  end

  Thread.new do
    loop do
      if h.value > 30
        h.value = 3
      else
        h.value += 1
      end
    end
  end
end

app.run