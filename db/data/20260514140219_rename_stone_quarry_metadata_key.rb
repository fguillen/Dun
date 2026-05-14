# frozen_string_literal: true

class RenameStoneQuarryMetadataKey < ActiveRecord::Migration[8.1]
  def up
    Kingdom.where("metadata ? 'starter_buildings'").find_each do |kingdom|
      starters = kingdom.metadata["starter_buildings"]
      next unless starters.is_a?(Hash) && starters.key?("stone_quarry")

      starters["quarry"] = starters.delete("stone_quarry")
      kingdom.update_columns(metadata: kingdom.metadata.merge("starter_buildings" => starters))
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
