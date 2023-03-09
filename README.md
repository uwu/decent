# decent
decent is a text user interface (TUI) library written in Ruby without the use of Curses or any external libraries.

decent is modeled after SolidJS's Signals (Observables), and a React-like workflow.

```ruby
require "decent"

Decent::App.new do
  count = ref 0
  
  text derived { "Count is: #{count.value}!" }
  
  # NOTE: We'll have interactions later! This is just a demo :)
  Thread.new do
    count.value += 1
  end
end
```