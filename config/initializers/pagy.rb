require "pagy"
require "pagy/extras/headers"
require "pagy/extras/overflow"

Pagy::DEFAULT[:limit] = 25
Pagy::DEFAULT[:overflow] = :empty_page
