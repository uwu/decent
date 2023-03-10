=begin require "./decent.rb"

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
      sleep 0.1
    end
  end
end

app.run
=end


require "./decent.rb"

app = Decent::App.new do
  count = ref 10000

  text derived { count.value.to_s }

  Thread.new do
    loop do
      count.value /= 10
      sleep 1
    end
  end
end

app.run

