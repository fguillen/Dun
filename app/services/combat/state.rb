module Combat
  State = Struct.new(
    :attacker_composition,
    :defender_aggregate,
    :starting_attacker_composition,
    :starting_defender_aggregate,
    :total_starting_hp_attacker,
    :total_starting_hp_defender,
    :terrain,
    :is_defender_home,
    :walls_level,
    :walls_hp,
    :rng,
    :log,
    keyword_init: true
  )
end
