require_relative "decent_tui"

Decent.tui do
  stack {
    flow {
      stack {
        table(
          ["header 1", "header 2", "header red", "header blue :D"],
          [
            ["a", "b", "c", "d"],
            ["e", "f", "g", "h"]
          ]
        )
        box
      }

      stack {
        table(
          ["First name","Last name","Age", "Gender"],
          [
            ["Tinu",      "Elejogun",   14, "F" ],
            ["Javier",    "Zapata",     28, "M" ],
            ["Lily",      "McGarrett",  18, "F" ],
            ["Olatunkbo", nil,          22, "M" ],
            ["Adrienne",  "Anthoula",   22, "M" ],
            ["Axelia",    "Athanasios", 22, "M" ],
            ["Jon-Kabat", "Zinn",       22, "M" ],
            ["Thabang",   "Mosoa",      15, "F" ],
            ["Rhian",     "Ellis",      12, nil ]
          ]
        )
        box
      }
    }
    box
  }
end
