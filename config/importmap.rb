# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# number-flow for animated numbers
pin "number-flow", to: "https://esm.sh/number-flow@0.5.10"
pin "number-flow/group", to: "https://esm.sh/number-flow@0.5.10/group"

# @floating-ui for tooltips
pin "@floating-ui/core", to: "https://esm.sh/@floating-ui/core"
pin "@floating-ui/utils", to: "https://esm.sh/@floating-ui/utils"
pin "@floating-ui/dom", to: "https://esm.sh/@floating-ui/dom"
