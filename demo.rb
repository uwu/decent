require "./decent.rb"

app = Decent::App.new do
  count = ref 1

  box do
    box do
      box do
        box do
          box do
            box do
              box do
                text derived { "Count is: #{count.value}! Also, decent is fucking sweet. Look at these sick-ass boxes."}
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
      sleep 0.07
    end
  end
end

app.run