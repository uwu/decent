require "./decent.rb"

app = Decent::App.new do
  count = ref 10

  box do
    box do
      box do
        box do
          box do
            box do
              box do
                text derived { count.value.to_s}
              end
            end
          end
        end
      end
    end
  end

  Thread.new do
    loop do
      count.value += 1
    end
  end
end

app.run