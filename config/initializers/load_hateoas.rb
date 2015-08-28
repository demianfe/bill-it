# -*- encoding : utf-8 -*-
HATEOAS = YAML.load_file("#{Rails.root}/config/hateoas.yml")[Rails.env]
