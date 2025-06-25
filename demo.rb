require_relative "decent_tui"

Decent.tui do
  box {
    stack {
      box {
      
      }.style.fg(32)

      box {
        
      }.style {
        fg 34
      }
    }
    flow {
      box {}
      box {}
    }
  }
end