class ProductionCheckpointJob < ApplicationJob
  queue_as :default

  def perform
    Kingdom
      .joins(:world)
      .where(worlds: { status: %w[grace active] })
      .where(eliminated_at: nil)
      .find_each do |kingdom|
        Stockpile::Checkpoint.call(kingdom)
      rescue => e
        Rails.logger.warn(
          event: "production_checkpoint.failed",
          kingdom_id: kingdom.id,
          error_class: e.class.name,
          error_message: e.message
        )
      end
  end
end
