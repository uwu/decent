require_relative "decent_tui"

Decent.tui do
  whatever = state "whatever"

  box { # THIS
    box { # THIS
      box {}
      box { # THIS
        label whatever # THIS
      }
      box {}
    }
  }
end